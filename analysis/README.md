# Ops Analysis: Auditing My Own Salesforce Org

I exported data from the music school org in this repo, built an operations analysis in Excel, and audited it for data-quality problems. Each problem I found is tied to the Salesforce change that would prevent it.

![Dashboard](dashboard.png)

**Live workbook (view only):** [(https://1drv.ms/x/c/d27ccacc197bb1fb/IQCWDMpl_WjsT6Tw-OnoNZKbAa4Kksup4_aSOf-8YwDJqsg?e=c8uBaH)]
**File:** `Music_Academy_Ops_Analysis.xlsx`

---

## The data

Exported from my Salesforce Developer Edition org on 10/14/2026. All people and contact details are fictional. [Back to the main project](../README.md).

| Object | Records |
|---|---|
| Lessons | 1,328 |
| Students | 182 |
| Instructors | 46 |
| Enrollment Inquiries | 140 |
| Locations | 3 (Red Bank, Brick, Toms River) |

## What the data says

1. **September looked like a collapse, and it wasn't.** Completed lessons fell from 90 in July to 31 in September. The reason was that 57 of September's lessons were never marked Completed or Cancelled. After cleanup, September (64) matches August (64).
2. **Brick cancels 18% of its lessons, almost double Red Bank's 10%.** 23 of Brick's cancellations came from instructors, not students.
3. **About 1 in 3 finished inquiries becomes a student (34.5%), not 50%.** The higher number came from 57 leads that had been sitting open for more than a month without being closed out either way. Another 19 inquiries never got a response at all.
4. **Red Bank brings in 46% of monthly revenue** ($12,860 of $28,060 from 143 active students).

## Data audit

Every count recalculates from the exported data, so the audit can be re-run on a fresh export.

| # | Issue | Count | Salesforce fix |
|---|---|---|---|
| 1 | Past lessons still marked Scheduled | 5 (was 93) | My validation rule (status must match the lesson date) only runs when a record is saved, so untouched lessons slip past it. A nightly scheduled Flow should flag them, with a list view the front desk clears weekly |
| 2 | Inquiries marked Converted with no linked student | 40 of 41 | The Inquiry to Student Flow sets the link, but these were marked Converted by data loads, not through the Flow. A validation rule requiring Converted Student when Status is Converted would force conversions through the Flow |
| 3 | Duplicate students | 3 pairs | The Student duplicate rule already warns on new duplicates (I tested it on two of these pairs), but these pairs came with the sample data. Custom objects can't use the standard merge, so cleanup is manual: move lessons to the record you keep, then delete the extra |
| 4 | Duplicate inquiries (same email) | 1 pair | Duplicate rule on Inquiry matching on email |
| 5 | Lesson booked with an instructor who doesn't teach that instrument | 7 | Validation rule on Lesson checking the instructor's Instruments Taught |
| 6 | Same lesson entered twice | 1 (was 2 conflicts) | Record-triggered Flow that blocks a second lesson for the same instructor at the same date and time |
| 7 | Two instructors sharing one email | 1 pair | Fix the record, then mark the Email field Unique |
| 8 | First response dated before the inquiry | 2 | Validation rule: First Response Date can't be earlier than Inquiry Date |
| 9 | Student marked Active with a future enrollment date | 1 | Add a Pending status, plus a validation rule blocking Active before the start date |
| 10 | Lessons that need a makeup but don't have one booked | 15 | The Cancellations dashboard already shows makeups owed. A record-triggered Flow that creates a makeup task when an instructor cancels would make sure someone acts on it |

Some details I'd point out:
- The duplicate students in row 3 share a parent email but have birthdays 7 months and 2 weeks apart. Siblings can't be born that close together, so each pair is one kid entered twice with a birthday typo.
- 5 of the 7 wrong-instrument lessons in row 5 are on the same date (3/11), which points to one bad import rather than separate mistakes. Those are also the 5 lessons left in row 1.

## Cleanup (10/14/2026)

The raw export had a lot of records that were never closed out, which made the trends misleading. I updated them using rules based on each record's own history, then loaded the changes back into the org with Data Loader, matching on record ID so nothing was duplicated.

**Lessons (89 updated):**
- Instructor had left (Inactive, and the lesson falls after their last recorded lesson): Cancelled by Instructor, makeup required.
- Student is Paused: Cancelled by Student.
- Everyone else: outcome based on that student's attendance history and that instructor's cancellation history, blended with academy-wide rates so one or two lessons don't decide it.
- The 5 lessons from the bad 3/11 import were left alone. They need to be investigated, not guessed at.

**Inquiries (57 updated):**
- Contacted for more than 30 days with no trial booked: closed as Not Interested or Unresponsive, based on that lead source's history.
- Trial Scheduled for more than 30 days: the trial happened, so closed as Converted, Not Interested, or Unresponsive based on that lead source's history.
- New with no response: left as New. Nobody contacted them, which is a finding in itself.
- Anything with activity in the last 30 days: left open.

| Metric | Before | After |
|---|---|---|
| Past lessons still Scheduled | 93 | 5 |
| September completed lessons | 31 | 64 |
| Inquiry close rate (finished inquiries) | 50.0% | 34.5% |

## How it's built

- **Excel tables** for each export, with helper columns for duplicate keys, response time, location names, and lesson month
- **XLOOKUP** to join objects (lesson → instructor, inquiry → location)
- **COUNTIFS, SUMIFS, AVERAGEIFS** for the audit counts and rates
- **Pivot tables and pivot charts** for the funnel, lesson health, instructor load, and revenue
- **A pinned "as of" date** instead of TODAY(), so the numbers don't change every time the file opens

## Judgment calls

- **Close rate counts finished inquiries only** (Converted, Not Interested, Unresponsive), so sources with a lot of recent leads aren't penalized. The tradeoff is that stale open leads don't count against a source, which is why the cleanup above mattered.
- **Response-time averages are skewed by outliers.** Instagram averages 22 days, but its median is 1 day. Two responses took 157 and 199 days.
- **Small samples.** Some lead sources have fewer than 15 finished inquiries, so source-level rates are directional only.

---

*AI use: I used Claude to review and debug my formulas, help design the cleanup rules, and draft parts of the written explanations.*
