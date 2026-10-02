# Project Notes: Music School CRM

These are my build notes for the Salesforce project in the [README](../README.md). They cover the errors I hit, what caused them, how I fixed them, and why I made the design choices I did. They are grouped by phase, roughly in the order I built things. All dates are 2026.

The sample data, the generated files I used to fix or extend it, and the scripts I used to cross-check data files were made with AI. I kept a raw log while building, and these notes were condensed from it with AI's help, so the wording is tighter than my log. The configuration, testing, debugging, and final decisions in the org are mine.

**Final org state:** 3 locations, 46 instructors (15 active after the roster trim), 181 students, about 1,330 lessons (including scheduled lessons through March 2027), and 139 enrollment inquiries.

**Start here:** if you only read three parts, read [4. Security model](#4-security-model), the [Aubrey Wilson email incident](#incident-the-turn-18-flow-erased-aubrey-wilsons-email-920) in section 5, and [9. Scheduled follow-up Flow](#9-scheduled-follow-up-flow-929).

Contents: [1. Data model and loads](#1-data-model-and-loads) · [2. Page layouts](#2-page-layouts) · [3. Validation rules](#3-validation-rules) · [4. Security model](#4-security-model) · [5. Minors' contact information](#5-minors-contact-information) · [6. Reports and dashboards](#6-reports-and-dashboards) · [7. Screen Flow](#7-screen-flow-inquiry-to-student-926) · [8. Apps and enrollment pipeline](#8-apps-and-enrollment-pipeline-926-to-928) · [9. Scheduled follow-up Flow](#9-scheduled-follow-up-flow-929) · [10. Pre-launch cleanup](#10-pre-launch-cleanup-929-to-101) · [11. Known limitations](#11-known-limitations)

---

## 1. Data model and loads

### Objects

- **Location**: the standard Salesforce Location object. Red Bank (LOC-001), Brick (LOC-002), Toms River (LOC-003).
- **Instructor**, **Student**, **Lesson**, **Enrollment Inquiry**: custom objects. Lesson uses auto-number names (`L-0000002`).

Every object has an External ID field (`LOC-001`, `INS-001`, `STU-0001`, `LSN-00001`, `INQ-0001`) so loads can match related records by ID.

### Relationships

- **Lesson → Student** and **Lesson → Instructor**: master-detail, with reparenting allowed on both. I wanted roll-up summaries on both parents (lesson counts, hours taught, no-show rates), and reparenting lets a lesson move to a substitute instructor.
- Tradeoff: that uses both master-detail slots on Lesson, so **Lesson → Location** has to be a lookup.
- **Instructor → Location** (`Primary Location`), **Student → Location** (`Home Location`), and **Enrollment Inquiry → Location** (`Requested Location`) are lookups.

### Initial load errors

| # | Object | Error | Cause | Fix |
|---|---|---|---|---|
| 1 | Instructor | `Cannot deserialize instance of double from VALUE_STRING value INS-001` | External ID field was created as a Number. The data is text. | Changed the field to Text with External ID. (Later I found Unique was not checked on the Instructor field. See "Duplicate instructors" below.) |
| 2 | Instructor | `Cannot deserialize instance of boolean from VALUE_STRING value active` | Status field was created as a Checkbox, but the data has words | Changed to a picklist (Active/Inactive) |
| 3 | Instructor | `Required fields are missing: [Instruments_Taught__c]` | INS-041 has no instruments listed, and the field was required | Record rejected. INS-041 was loaded in a later run (see "Recovery verified"). |
| 4 | Student | `Required fields are missing: [Status__c]` and `invalid email address: not-an-email` | Planted data problems, caught by the schema as intended | 181 of 183 loaded. 2 rejected as designed. |
| 5 | Enrollment Inquiry | `Could not find Student__c with Student_External_Id__c of ''` | A blank lookup column was mapped, so the loader tried to match an empty string | Unmapped `Converted_Student_Id` |
| 6 | Enrollment Inquiry | About 115 `DUPLICATE_VALUE` errors | A partial earlier load left the org in an unknown state | Switched from Insert to Upsert on External ID, so a re-run can't duplicate |
| 7 | Lesson | `'LSN-00001' is not valid for the type xsd:double` | Same Number vs. Text mistake, this time on Lesson | Changed to Text |
| 8 | Lesson | `'11:00' is not a valid value for type xsd:time` | Source times had no seconds | Changed the source format to `HH:MM:SS.000Z` |
| 9 | Lesson | `Number of fields in header is different from the row (11 vs 10)` on 19 rows | Misleading error. The source CSV was checked directly and all 831 lines had exactly 11 fields. The real cause: 17 rows pointed to INS-041, which hadn't loaded, and 2 belonged to STU-0067, which was rejected for its bad email. | Load parent records first. With two master-detail parents, a missing parent on either side blocks the lesson. |

Initial load results (later superseded): Locations 3/3, Instructors 45/46, Students 181/183, Lessons 811/830, Enrollment Inquiries loaded by upsert.

What I took from the first load:

- An error message points somewhere, but not always at the cause. Error 9 looked like a CSV structure problem and was really a missing parent record. Checking the source file directly is what turned the investigation around.
- Load parents before children, and confirm the parent load actually finished. One rejected instructor quietly broke 17 lessons two loads later.
- Use Upsert when there is an External ID. It makes loads safe to re-run after a partial failure.
- I made the same Number vs. Text mistake on two objects. A schema review before loading would have caught both at once.

### Checking the source data before building security

Before designing sharing, I checked my assumptions against the source CSVs, using a script to cross-check all 830 lessons against their students and instructors.

1. **Two lesson failures blamed on instructors were really student failures.** LSN-00295 and LSN-00296 both belong to STU-0067, which was rejected at the student load. All 19 unloaded lessons were now explained: 17 for INS-041 and 2 for STU-0067. (LSN-00296 is also dated three months before STU-0067's enrollment date. That one wasn't planted.)
2. **Lesson location follows the student, not the instructor.** Lesson location didn't match the instructor's Primary Location on 508 of 830 lessons, but didn't match the student's Home Location on only 1. The generator never lined instructors up with locations, so the one planted wrong-location lesson was lost in the noise. Sharing based on Instructor → Primary Location would have cut instructors off from most of their own lessons.
3. **Most instructors didn't teach the lesson's instrument.** 706 of 830 lessons had an instructor whose `Instruments Taught` didn't include that instrument. The cause was in the raw `lessons.csv` (for example, LSN-00001 is a Trumpet lesson assigned to INS-031, who teaches Flute, Saxophone, and Cello), so the field mapping was fine. Students also had up to 6 different instructors, which isn't how a lesson academy works.
4. **Lesson `Instrument` matched Student `Primary Instrument` on all 830 lessons.** It's a copy of the parent's value, the same drift risk I rejected for name text fields. It only makes sense if students take more than one instrument.
5. **Instructor status field.** Load error 2 and my Rule 3 notes described this field differently. The instructor export later confirmed the field in use is `Active__c`.

### Scope decision: instructors are not Salesforce users

Salesforce is the system of record for the academy's admin team. Instructors would use a separate teaching and scheduling tool that pulls rosters and schedules from Salesforce.

Why: licensing 45+ instructors is expensive for a small school, most only need "my students, my schedule," and they don't need billing, inquiries, or other locations' data. The security model is built around admin roles and scoped by Student Home Location (which the data supports on 829 of 830 lessons). The connection to that separate tool is only a design idea. I did not build it.

### Lesson data realignment

I regenerated the instructor assignments in `lessons.csv` with a script, then checked the output with a second script instead of trusting it.

Rules applied: the instructor must teach the lesson's instrument; one instructor per student; prefer an instructor at the student's home studio, otherwise the nearest studio; only active instructors with instruments listed (so INS-041 gets no lessons); hired before the student's first lesson; within `Max Weekly Students`; duplicate students (STU-0181/0182/0183) get the same instructor as their originals; and no overlapping bookings except the planted cases.

Verified results:

- 830 rows. Only Instructor, Start Time, and one Lesson Date changed.
- Unqualified instructor assignments: 706 → 0.
- Lessons away from the instructor's primary studio: 508 → 119. All 119 come from 25 students whose instrument has no instructor at their home studio (mostly Toms River, plus Cello at Red Bank and Violin at Brick). That's a real roster gap.
- INS-041 lessons: 17 → 0, so those lessons are no longer blocked.
- Two start times moved to clear new overlaps (LSN-00196, LSN-00230).
- The full before/after record is in `lesson_changes.csv`.

Planted issues, corrected and moved:

- The original "double-booking" (LSN-00501/00502) was the same student booked twice. I kept it as a duplicate lesson. The original file also had 3 accidental double-bookings.
- New true double-booking: LSN-00012 and LSN-00036, two students with instructor INS-001 on 2026-09-22 at 15:30, at two different studios. Both are future Scheduled lessons.
- Inactive instructor: moved from a completed March lesson (not really a problem) to LSN-00003, a future Scheduled lesson assigned to inactive INS-019.
- The wrong-location lesson (LSN-00151), blank duration (LSN-00311), past-but-Scheduled lessons, and completed-without-notes rows were left alone.

### Load errors during the realignment

| # | Object | Error | Cause | Fix |
|---|---|---|---|---|
| 10 | Lesson | `'19:00' is not a valid value for the type xsd:time:Start_Time__c` on all 814 rows | I upserted `lesson_changes.csv` (the audit file) instead of `lessons.csv`. The 814 row count gave it away, since the load file has 830. The audit file stores times as `HH:MM`. | Nothing was written. Re-ran against `lessons.csv`. |
| 11 | Lesson | `Foreign key external ID: INS-032 not found for field Name in entity Instructor__c` on all 830 rows (Data Import Wizard) | The Instructor relationship was set to match on the Instructor Name field, but the CSV has External IDs. After the name backfill, Name holds "Kai Okafor" and so on, so nothing matched. | 0 rows written. Re-map Instructor to match on External ID. |
| 12 | Lesson | `Student: id value of incorrect type: STU-0001` on all 830 rows | The Student column was mapped straight to the Lesson's Student field, which expects an 18-character Salesforce ID, instead of through the related object's External ID. The field's API name (`Student_External_Id__c`) made this easy, because it looks like an External ID but is the master-detail field. | 0 rows written. Re-mapped Student, Instructor, and Location through their related External ID fields. |

Notes on these:

- **Error 10:** check the row count and header before mapping. If the times had been in the right format, this load would have succeeded and inserted the 17 INS-041 lessons with no Status, Location, or Duration. The type error prevented a worse silent failure.
- **Tools:** up to this point, every load was in dataloader.io (MuleSoft's web tool), not Salesforce's desktop Data Loader. They are different products. I hit dataloader.io's free monthly record limit during the lesson re-upsert and moved to the desktop Data Loader. The wrong-file load may have used 814 records of quota while writing nothing. Test with 5 to 10 rows first.
- **Error 11:** the message named both the value and the field it searched, so reading the whole message gives the answer. The wizard offered External ID matching for Student and Location but not Instructor. On the Instructor External ID field, External ID was checked but **Unique was not**. Next hypothesis (not confirmed): the wizard only offers External IDs that are also Unique. Unique is the right setting either way.
- **Error 12:** the `Status` column was also blank on all 830 rows in that file, most likely cleared while the file was open in a spreadsheet. It had to be restored before reloading. The confusing relationship field name caused a real mapping error here, so naming turned out to matter more than I expected.

### Duplicate instructors

Turning on Unique for the Instructor External ID was blocked by an existing duplicate value. The source CSV has no duplicates, so the duplicate was created in the org, most likely by the instructor load running more than once while Unique was off.

The list view sorted by External ID then showed **two records for every instructor**. Most second copies showed a record ID as their Name, so they were created after the manual name backfill. The original lesson load matched instructors by External ID and succeeded, so the duplicates probably came after it, and the originals should hold the lessons. That needed checking with data, not Name.

Custom objects have no native merge (merge is for standard objects like Accounts, Contacts, Leads, and Cases), so the manual version is: move the children, then delete the duplicate. Deleting a master-detail parent also deletes its lessons, so each duplicate had to have 0 lessons first.

What I did:

- Got the desktop Data Loader working. The first export failed with `unexpected token: '/'`. SOQL date-times must be ISO 8601 in UTC (`2026-09-14T18:06:00Z`), not local format. I dropped the filter and exported all instructors.
- Built **Lesson Count** (`Lesson_Count__c`), a roll-up summary on Instructor that counts lessons. This was my first roll-up field, and it's only possible because Lesson → Instructor is master-detail.
- Used Lesson Count to tell each pair apart: 0 lessons = duplicate. INS-019 and INS-033 had 0 on both copies (they had no lessons in the source).
- I decided what to delete by lesson count, not created time, because lesson count directly checks what makes a master-detail delete safe.

### Accidental delete of all instructors

- I deleted **all** instructors instead of only the duplicates. Because Lesson → Instructor is master-detail, every lesson was deleted with them.
- I recovered with Data Loader **undelete** from the Recycle Bin. Restoring a master also restores the detail records deleted with it. The duplicates stayed deleted.
- **James Moore (INS-023) failed to restore.** He breaks Validation Rule 3 (active, no background check date), which is a planted compliance issue. His lessons were still in the Recycle Bin, tied to his original record ID.
- I didn't re-import him. A new insert creates a new record ID, and his original lessons couldn't be reattached to it. They'd be lost when the Recycle Bin purges after 15 days. Instead I turned Rule 3 off, undeleted his original record, and turned the rule back on. I left the missing background check date in place as the planted issue rather than inventing a date to pass the rule.

What I took from it:

1. Check the row count and contents of a delete file before running it. Delete is the one operation where testing with a sample isn't optional.
2. The Recycle Bin and undelete are the safety net, but only for 15 days, and a restore can fail on validation.
3. Turning off a validation rule for data recovery is a legitimate admin move, but it has to be documented and turned back on right away.
4. Master-detail made the delete destructive, but it also made the recovery clean, since the children came back with the parent.

### Recovery verified

From an instructor export:

- 46 instructors, 46 unique External IDs. No duplicates left.
- James Moore restored with his 16 lessons.
- Lesson Count total: **828**, which is the 830 source lessons minus STU-0067's 2. Every instructor's count matched the source exactly, so the delete and undelete lost nothing.
- INS-041 (Jordan Patel) **is** in the org. It was created about 90 minutes after the other instructors, in a later load run, with its 17 lessons. So the initial "45/46 instructors, 811/830 lessons" figures were out of date.
- The export confirmed the instructor status field in use is `Active__c`.

### Realignment upsert and the Rule 3 surprise

First successful run with the desktop Data Loader: **791 of 830 succeeded, 39 failed.**

| Count | Error | Cause | Expected? |
|---|---|---|---|
| 6 | `The lesson can't be completed in future/scheduled for the past` | Rule 1: LSN-00004, 00089, 00205, 00416, 00621 (planted) and LSN-00103 (went stale on 9/15) | Yes |
| 1 | `Completed lesson needs a listed duration` | Rule 4: LSN-00311 (planted) | Yes |
| 2 | `Foreign key external ID: stu-0067 not found` | STU-0067 never loaded | Yes |
| 30 | `Background check must be completed before the teacher is active` | An Instructor rule firing on a Lesson load | No |

Cause of the 30: every one of them was moving either to James Moore (14 lessons) or away from him (16 lessons). Exactly 30, no exceptions. Moving a lesson recalculates the `Lesson Count` roll-up on both the old and new instructor. A roll-up recalculation is a save on the parent record, so the parent's validation rules run. James Moore is active with no background check date, so Rule 3 rejects his roll-up update and the lesson save fails with it.

The roll-up I had built an hour earlier for the duplicate cleanup created a hidden dependency: a validation rule on one object could now block saves on another. Nothing in the Lesson error names the Instructor. Matching the failed rows back to one parent record is what exposed it.

The problem with Rule 3: it fires on every save of a noncompliant instructor, including saves nobody made on purpose (system roll-up recalculations). A compliance rule should stop someone from making an instructor active without a background check. It shouldn't freeze every record related to one that's already in that state. The two options were: turn Rule 3 off, re-run the 30, and turn it back on (quick, but the problem returns with every future lesson change for him), or rescope Rule 3 to fire only when the record is new or when `Active__c` or `Background_Check_Date__c` changes, with a report to surface existing noncompliant records.

My call: the quick option. I turned Rule 3 off, re-ran the 30, and turned it back on. Rescoping the rule is on the Known limitations list. The re-run left only the 9 expected failures (6 for Rule 1, 1 for Rule 4, 2 for STU-0067). The 7 validation-blocked lessons kept their original, unqualified instructors. They get fixed on touch once their status or duration is corrected, which is how the rules are meant to work.

### Final verification: passed

Instructor export after the realignment: Lesson Count total 828, and all 46 instructors matched the expected count exactly (compared by script against the realigned file, with the 7 blocked lessons on their original instructors and STU-0067's 2 excluded). INS-023 = 14, INS-041 = 0, INS-001 = 31, INS-019 = 1.

Worth knowing for reports:

- INS-039 (Caleb Ramirez) has 0 lessons. He was hired 2026-06-30, after his qualified students' first lessons, so the hire-date rule excluded him. A real "new hire with no students" case.
- INS-044 (Priya Carter) has 1 lesson, LSN-00311 (blocked, still unqualified).
- Load is uneven (Aiden Hill 50, Adrian Byrne 43), driven by who teaches the most popular instruments at each studio.

### Student verification: passed

Export: 181 students, 181 unique External IDs. Missing only STU-0067 (bad email) and STU-0091 (blank status), both rejected as designed. Age, Status, Skill Level, Primary Instrument, and Lesson Frequency match the source on every record. Name = Full Name on all 181.

Planted issues still present: STU-0045 blank age, STU-0183 "LOGAN" in caps, and the STU-0181/0182/0183 duplicates. Salesforce trimmed the trailing space in STU-0182's last name on load, so that duplicate is now an exact name match with STU-0058 instead of a near match.

---

## 2. Page layouts

I built custom Lightning record pages and page layouts for all five objects.

### Highlight panels

- **Location:** Location Type
- **Instructor:** Instruments Taught, Primary Location, Max Weekly Students
- **Student:** Primary Instrument, Skill Level, Status, Home Location, Age
- **Lesson:** Student, Instructor, Instrument, Lesson Date, Location, Status
- **Enrollment Inquiry:** Student Age, Interested Instrument, Requested Location, Status

### Conditional field visibility (Dynamic Forms)

1. **Lesson → Makeup Required** shows only when Status is No Show, Cancelled by Student, or Cancelled by Instructor. It means nothing on a completed or scheduled lesson.
2. **Student → Guardian First Name, Last Name, Phone, Email** show only when Age ≤ 17. Guardian info doesn't apply to adult students. Checked on Omar Clark (age 24): the fields were hidden. (This was changed later. See "Parent/Guardian Pays" in section 5.)
3. **Enrollment Inquiry → ConvertedStudentId** shows only when Status = Converted.
4. **Lesson → Instructor Notes** shows only when Status = Completed. Notes don't apply to a scheduled, cancelled, or no-show lesson.

Hiding fields that don't apply cuts noise for users and prevents data from being entered where it doesn't belong, so it helps data quality too.

Other Lesson page changes: added Notes & Attachments and Files related lists (for sheet music, practice materials, or recordings), removed the standard Sales Cloud buttons (New Contact, New Opportunity, Edit) from the highlight panel, and removed an empty System Information column.

### Record names

Lookup and master-detail fields display the parent record's **Name** field. Students and instructors were loaded without a Name, so Name defaulted to the record ID (`a07ak00001rZMqs`). Lessons showed unreadable IDs instead of people's names.

Rejected workaround: separate text fields on Lesson (`Student Name`, `Instructor Name`). I built them and then removed them. A text copy drifts (a lesson moved to a substitute keeps the old name), isn't clickable, can't reach related fields in reports, and creates two sources of truth.

Fix: a record-triggered Flow on Student (`Update Record to be Name`) sets `Student Name` = `Full Name`, and a matching Flow on Instructor (`Change Instructor Name`) does the same. Both started as drafts from Salesforce's built-in Flow generation, and I reviewed and adjusted them. A record-triggered Flow only fires on records saved after it's active, so the roughly 180 existing students and 45 instructors needed a backfill. I used mass inline edit from the list view, in batches of 50 and then 100. Students and instructors now show real names, and Lesson shows clickable Student and Instructor links.

Lesson keeps auto-number names (`L-0000002`). A lesson has no natural name. Something like "Aurora White, Trumpet, 2/9/2026" would repeat fields already on the record and drift if any of them changed. Auto-number fits transactional records.

---

## 3. Validation rules

### Changing Lesson Status from Text to Picklist

Changing the field type in place was blocked: `You can't change this field's data type because it's referenced by: Lightning Pages: Lesson`. The Dynamic Forms visibility rules for Makeup Required and Instructor Notes filter on Status, and a field used in a visibility filter counts as a page reference even when it isn't displayed.

Instead of fighting the dependency, I migrated through a new field: created a new picklist field, moved the data, checked it was complete, repointed the visibility rules and layouts, and retired the old text field. That's also how a type change would have to work in a production org.

### Rule 1: Lesson status and date must agree

Blocks a future lesson marked Completed and a past lesson still marked Scheduled.

```
AND(
  NOT(ISBLANK(Lesson_Date__c)),
  OR(
    AND(
      Lesson_Date__c > TODAY(),
      ISPICKVAL(Status__c, "Completed")
    ),
    AND(
      Lesson_Date__c < TODAY(),
      ISPICKVAL(Status__c, "Scheduled")
    )
  )
)
```

Why: 5 lessons in the source data were in the past but still Scheduled, so completion numbers were quietly wrong and nobody knew whether those lessons happened.

Build notes: the first draft had the logic reversed and would have blocked every valid record, and a direct `=` on the picklist broke right after the Status migration (see formula lessons below). The `ISBLANK` guard keeps lessons with no date from tripping the rule. The rule doesn't flag existing bad records, but it blocks saving them until they're fixed. I chose that on purpose to force cleanup when a record is touched. (Section 6 shows the cost of that choice with LSN-00621.)

### Rule 2: Guardian contact required for minors (Student)

Original version:

```
AND(
  NOT(ISBLANK(Age__c)),
  Age__c <= 17,
  OR(
    ISBLANK(Guardian_First_Name__c),
    ISBLANK(Guardian_Last_Name__c),
    ISBLANK(Guardian_Phone__c),
    ISBLANK(Guardian_Email__c)
  )
)
```

Why: a minor enrolled with no reachable adult is a safeguarding and liability problem. The source data had exactly this case.

Decision: all four guardian fields are required. A looser version (name plus phone or email) would still leave the guardian reachable, but I chose the stricter version for a child-safety rule. The `ISBLANK(Age__c)` guard was there because one student had no age. This guard turned out to be a real gap (see "Rule 2 revision" in section 4).

### Rule 3: Background check required for active instructors

```
AND(
  ISPICKVAL(Active__c, "Active"),
  ISBLANK(Background_Check_Date__c)
)
```

Why: an active instructor working with children with no background check on record is a direct risk to the school. The source data had one such instructor.

`Active__c` started as a Text field, so the first version was `Active__c = "Active"`, an exact string match that `active` or a trailing space would slip past. On 9/28 I converted the field to a picklist and changed the rule to `ISPICKVAL()`. It could still be renamed `Status__c` to match the other objects, since a field called "Active" holding Active/Inactive reads like a checkbox.

See section 1 for how this rule later blocked a lesson load through a roll-up.

### Rule 4: Duration required on completed lessons

```
AND(
  ISPICKVAL(Status__c, "Completed"),
  ISBLANK(Duration_Minutes__c)
)
```

Why: a completed lesson with no duration can't be billed or reported. The source data had one (LSN-00311).

Tradeoff: making Duration required on the object would catch the gap at scheduling time and make this rule unnecessary. I kept the conditional rule so a time slot can be booked before the duration is confirmed, and accepted that the gap shows up later.

Edge case: `ISBLANK()` doesn't treat 0 as blank, so a completed 0-minute lesson would pass. Not guarded.

### Formula lessons

These came up again and again:

1. A validation rule fires when TRUE means invalid.
2. Picklists need `ISPICKVAL()` or `TEXT()`, never `=`.
3. `= NULL` and `= BLANK` aren't valid. Use `ISBLANK()`.
4. Boolean operators don't distribute. `(A) || (B) || (C) = BLANK` doesn't compare all three. Each side of an OR has to be a complete expression.
5. I prefer `AND()` and `OR()` over `&&` and `||`, because precedence is explicit and it's easier to read.
6. `Incorrect parameter type for function 'AND()'. Expected Boolean, received Text` means a field isn't the type I assumed. Check the field definition before debugging the formula.
7. Guard for blanks on any field used in a comparison when the data has nulls.

### Rules added later

- **Minors can't have a Student Phone**, **Parent/Guardian Pays needs contact info**, and **Birthday required on new students**: see section 5.
- **Rule 2 revision** (unknown age treated as a minor): see section 4.

---

## 4. Security model

### Personas

I modeled the personas on the real structure of the music academy I worked at, instead of a generic "regional manager," so I could explain each access decision from experience: Owner, Music Director, Office Director, Enrollment Director, Marketing Director, and a Front Desk user at each of the three studios. The admin (me) is a System Administrator.

The persona table went through three drafts. What changed between them, which shaped the final design:

- Only Front Desk is limited by location. The directors differ mainly in object and field permissions, not in which records they see.
- Each object needed Create, Read, Edit, and Delete spelled out, and "sensitive fields" had to name actual fields (Hourly Rate, Background Check Date, Monthly Rate, guardian and minors' contact).
- **Field-level security is per field, not per record.** It can't hide Student Email only when the student is a minor. Dynamic Forms visibility isn't security either: hidden fields still show in reports, list views, and exports. This led to the separate minor email field in section 5.
- Blocking Front Desk from minors' contact info would break their daily job (cancellations, makeups, scheduling calls).
- Lesson access is Controlled by Parent, so it follows Student access.
- Inquiries: every front desk sees every studio's inquiries. Families call whichever studio answers. Queues and routing decide who works it.

### Profile vs. permission sets vs. roles

- **Profile:** what a user can do (object and field permissions, system permissions, license, login policies). Exactly one per user.
- **Permission sets:** extra permissions on top. Many per user.
- **Role:** which records a user can see through the hierarchy. It doesn't grant object or field permissions.

Roles alone can't replace per-persona permissions. I chose **one minimal base profile plus a permission set per job**, which is Salesforce's recommended direction and avoids repeating changes across many profiles.

Rejected alternative: a separate profile for the Owner. A second profile is only justified for things that live only on profiles (license, login hours or IP ranges, session and password policy, default app). The Owner's extra access (Delete, View All, broader edit) is object permissions, which belong in a permission set.

Final shape:

- **School Admin Team** profile (Salesforce Platform license) for every non-admin user, including owners. All object permissions and field-level security removed from it. Access comes only from permission sets.
- Permission sets built: **Front Desk**, **Marketing Director**, **Office Director**, **Owner**. Enrollment Director was added later with the enrollment pipeline. Music Director has a role but no permission set yet.

Ownership note: every record was owned by my admin user, since I loaded everything. The role hierarchy only opens records upward from their owner, so the hierarchy alone gives front desk and directors nothing. Record access has to come from sharing rules.

### Marketing Director

I first cloned the standard Marketing User profile. It had Create on Instructors (Marketing shouldn't add staff), and it's a Salesforce-license profile that brings Accounts, Contacts, Leads, and Campaigns and uses one of the 2 full licenses. Location wasn't in its custom object list because Location is the standard object (Read was set under Standard Object Permissions).

I rebuilt it on a Salesforce Platform license and removed API Enabled, Apex REST Services (both let a user pull data outside the UI), View Setup and Configuration, Create Public Links, Mass Edits from Lists, and Invite Customers To Chatter.

Its settings then moved into the **Marketing Director permission set**:

| Object | Access | Field notes |
|---|---|---|
| Student | Read | Minor Email: none. Monthly Rate: none. Guardian fields: Read. |
| Lesson | Read | Instructor Notes: Read |
| Enrollment Inquiry | Read, Create, Edit | External ID: read only (edit removed) |
| Location (standard) | Read | |
| Instructor | Read | Hourly Rate: none. Background Check Date: removed. |

Decisions:

- Student, Lesson, and Instructor are Read only, since this is a reporting role.
- **Guardian contact fields: Read, kept.** Marketing to existing families (re-enrollment, events, promotions) needs guardian phone and email. A future option is a `Marketing Opt Out` checkbox.
- Integration keys like Inquiry External ID should be read-only for business users. Editing one breaks upsert matching.
- Instructor Notes: Read, accepted.
- **Export Reports stays on the shared profile** (small team, low risk, frequent need).
- **Mass Email moved off the profile** and into the Marketing Director permission set only. It was the first job-specific system permission moved off the base profile.

Edit checkmarks on required fields and master-detail fields are automatic and can't be removed. Without object Edit, they grant nothing.

### Front Desk

Decision: front desk does not edit instructors.

Problems in the first draft, and fixes:

1. Enrollment Inquiry had Delete, View All Records, and Modify All Records. That contradicts the persona (no delete), and Modify All ignores sharing entirely. Removed. Cross-studio inquiry visibility comes from the org-wide default instead.
2. The Lesson Location field had no access, so front desk couldn't see or set where a lesson happens. Changed to Read/Edit.
3. Location object set to Read only. Front desk shouldn't edit studio records.
4. Instructor Notes on Lesson changed back to Edit. Instructors aren't users, so front desk enters notes for them.
5. Tab settings were unchecked. Set Available and Visible for all objects in both permission sets.

For reference: View All Records and Modify All Records ignore sharing (Modify All is effectively admin rights on that object), and View All Fields ignores field-level security, which on Student would expose Minor Email.

I used one Front Desk permission set, not one per studio. Permission sets can't filter records by location, so three copies would be identical. Location scoping is a sharing job.

### Organization-wide defaults

The org-wide default is the most restrictive access anyone should have. Sharing rules, roles, and permissions only open access up from there.

| Object | Default | Why |
|---|---|---|
| Student | Public Read Only | Everyone can read every studio's students. Edit on your own studio comes from sharing rules. |
| Location | Public Read Only | Everyone needs to see studios. Only a few people maintain them. |
| Instructor | Public Read Only | Changed from my first plan of Public Read/Write. The default should be the most restrictive baseline, or the next permission set that gets Instructor Edit silently gets every record. |
| Enrollment Inquiry | Public Read/Write | Any front desk may take a call for any studio. Routing decides who works it. |
| Lesson | Controlled by Parent | Required by master-detail |

When I built the first sharing rule, the Sharing Settings page showed Student was actually **Public Read/Write**, not the Read Only I had planned. That meant anyone with Edit permission could already edit every student, so the rule granted nothing. I changed Student to Public Read Only, and location scoping started working.

### Role hierarchy

```
Owner
├── Enrollment Director
├── Marketing Director
├── Music Director
└── Office Director
    ├── Front Desk - Red Bank
    ├── Front Desk - Brick
    └── Front Desk - Toms River
```

Naming fixes:

- The third studio role was named "Asbury Park," but the third studio (LOC-003) is Toms River. Sharing rules pair studios with roles, so a name mismatch invites a wrong rule. Renamed to Front Desk - Toms River.
- The role was "Office Manager" while the persona and permission set were "Office Director." Renamed to Office Director so the name matches everywhere.
- "VP/Owner" renamed to Owner everywhere.

### Sharing by studio: the Home Studio picklist

Each front desk should edit only its own studio's students. A student's studio is the `Home Location` lookup, and criteria-based sharing rules can't use lookup fields (except lookups to users or queues). I confirmed it in the org before building a workaround: Home Location wasn't offered as criteria in a Student sharing rule.

Fix: a `Home Studio` restricted picklist kept in sync with Home Location by a Flow, used as the sharing criteria.

- A one-time upsert alone wasn't enough. It would fill existing records once, but new students and location changes would leave the picklist stale, and a stale picklist in a sharing rule gives the wrong front desk edit access. It needed a sync Flow as well.
- Rejected: replacing the Home Location lookup with a picklist. That loses the relationship to the Location record (reports, related lists, Location fields).
- Rejected: owner-based sharing with a per-studio user or queue as owner. Not realistic with the license count, and it overloads what ownership means.

**Home Studio sync Flow** (record-triggered on Student, create or update, Fast Field Updates). Problems across drafts:

1. `ISCHANGED()` is always false on create, so with `ISCHANGED(Home_Location__c)` alone, new students (the main case) never got a Home Studio. Changed to `OR(ISNEW(), ISCHANGED(...))`.
2. Matching on Location Name ("Brick Studio") breaks if a studio is renamed. Changed to the Location External ID (LOC-001/002/003).
3. The default outcome did nothing, so clearing Home Location left the old studio and its edit access in place. My first default outcome cleared both Home Studio and Home Location, which would erase a Home Location just entered for any studio outside the three branches. A sync Flow should only write its own target field, so I removed the Home Location assignment.
4. Existing students only got Home Studio if their location changed. Adding `PRIORVALUE()` inside the `OR()` doesn't work: it returns the old value, not TRUE/FALSE, and only works on the record's own fields.
5. My next try checked `ISBLANK({!$Record.Home_Location__r.Location_External_Id__c})`, which tests for no location. The intended check is whether Home Studio is blank.

Final entry condition:

```
OR(ISNEW(), ISCHANGED({!$Record.Home_Location__c}), ISBLANK(TEXT({!$Record.Home_Picklist__c})))
```

`TEXT()` is needed because `ISBLANK()` doesn't accept picklists. Any save of a student with no Home Studio now fills it in, so a no-change upsert can backfill everything.

Naming note: the field label is "Home Studio" but the API name is `Home_Picklist__c`. Changing an API name later means updating every Flow and rule that uses it.

**Backfill: passed.** 1-record test, then 5 records, then all students, using an upsert with only the External ID mapped. The Flow filled Home Studio on each save.

### Rule 2 revision: unknown age treated as a minor (9/17)

During the Home Studio backfill, **STU-0009 (Ryan Harris) updated successfully**. I expected Rule 2 to block him, since the source data has a guardian name but no guardian phone or email.

- Cause: STU-0009 had a blank Age (no Birthday), so Rule 2's `NOT(ISBLANK(...))` guard skipped him entirely.
- Why his Birthday was missing (likely): the Birthday load would have made him 13, which makes Rule 2 apply, and his guardian phone and email are blank. So Rule 2 most likely rejected the birthday load for his record. The rule blocked the data fix that would have made it apply to him.
- Design gap: any existing student with no Birthday skipped the child-safety rule. Unknown age was being treated as adult.
- Scope check: only STU-0009 and STU-0045 had a blank Birthday. STU-0045 has full guardian info in the source, so a stricter rule wouldn't lock it.

Rewritten on 9/17 so unknown age counts as a minor:

```
AND(
  OR(ISBLANK(Age_New__c), Age_New__c <= 17),
  OR(
    ISBLANK(Guardian_First_Name__c),
    ISBLANK(Guardian_Last_Name__c),
    ISBLANK(Guardian_Phone__c),
    ISBLANK(Guardian_Email__c)
  )
)
```

My first attempt used `AND` as a word between two expressions, which is a syntax error. `AND` is a function (or use `&&`).

Tests, all passed: STU-0009 blocked, STU-0045 saves, adult with no guardian saves, minor with full guardian saves.

STU-0009 now can't be edited until his birthday and guardian contact are entered. The real fix is to get them from the family, not to turn off the rule to force data in.

### Test users

- **Add Multiple Users** failed: "No Salesforce CRM Content User Licenses Available." That page assigns the CRM Content feature license by default, and the org had none left. I created users one at a time with CRM Content unchecked.
- With 5 Salesforce Platform licenses left, one user per persona wouldn't fit. I spent licenses on the users that prove the design and covered the rest by swapping role and permission set.
- Usernames must be unique across all Salesforce orgs, so I used a project domain (`@musicschoolqs.com`). Deactivating a user frees a license; freezing doesn't.

| User | Role | Permission set | What it proves |
|---|---|---|---|
| Marketing Director | Marketing Director | Marketing Director | Minor Email hidden on the record and in Report Builder |
| FrontDesk Brick | Front Desk - Brick | Front Desk | Edits own-studio students, read only on others |
| FrontDesk RB | Front Desk - Red Bank | Front Desk | Same rule from the other side |
| Office Director | Office Director | Office Director | Cross-studio edit, instructor edit |
| school owner | Owner | Owner | Top of hierarchy, delete rights |

### Issue: Brick front desk saw no students

Logged in as FrontDesk Brick, the Students tab showed nothing. New User only sets profile and role, and the School Admin Team profile has no object permissions on purpose. Without the Front Desk permission set, the user had no Read on Student, so sharing and defaults didn't matter. Sharing only matters once the user has object access in the first place. Resolved after fixing the user's access.

### Test: location-scoped edit (9/17)

| User | Adrian Chen (Brick) | Adrian Lewis (Red Bank) |
|---|---|---|
| FrontDesk Brick | Edit saved | Blocked: "you don't have the necessary privileges to edit this record" |
| FrontDesk RB | Blocked, same error | Edit saved |

The Public Read Only default plus the Home Studio sharing rules give each front desk edit on its own studio and read on the others. The pencil icons still show on records you can't edit, because Lightning shows them based on object permissions and checks record access at save. That's expected.

### Home Studio off the page, and read only everywhere

Home Studio only exists for sharing criteria, so I removed it from the Student page. That alone is UI only, so I also set **Home Studio to read only in every permission set**. A user who edits Home Studio directly skips the sync Flow (which only fires on create, a Home Location change, or a blank Home Studio). The picklist and the lookup would disagree, and sharing would follow the wrong studio. The Flow can still write to it because record-triggered flows run in system context and aren't blocked by field-level security. Every new permission set gets Home Studio as read only.

**Transfer test: passed.** As FrontDesk Brick, I changed Adrian Chen's Home Location to Red Bank Studio. The first save succeeded, the Flow set Home Studio to Red Bank, and a second save was blocked ("you don't have the necessary privileges"). Brick lost edit as soon as the student transferred. The page stayed in edit mode after the first save, which made it look like Brick could keep editing. The UI doesn't re-check access until the next save.

Design question this raised: a transfer is one-way for the sending studio. If Brick moves a student by mistake, Red Bank, the Office Director, or the Owner has to move them back. Options were to accept that (transfers are rare), or add a validation rule allowing Home Location changes only for users with a custom permission such as `Transfer_Students`.

### Office Director (9/17)

As built: Instructor Read/Create/Edit with Hourly Rate and Background Check Date editable, Student Read/Create/Edit with Minor Email access, Enrollment Inquiry read only, Lesson Read/Create/Edit with no Delete (cancellations use Status).

Changes after the first draft:

1. **Location set to Read only.** Location External ID can't be locked with field-level security, and the Home Studio Flow matches on LOC-001/002/003. One edit to that value would break studio sync and sharing for every new student.
2. **Home Studio changed from hidden to Read.** The Office Director is the person who troubleshoots "why can't Brick edit this student?", and that field is the answer.
3. **Hourly Rate: Office Director keeps edit.** The academy has no payroll role, so pay sits with the Office Director. Marketing and front desk can't see it.
4. Lesson relationship fields have API names like `Student_External_Id__c`, but they're master-detail and lookup fields, not External IDs. Logged as tech debt.

| Test (as Office Director) | Result |
|---|---|
| Edit Brick and Red Bank students, move Adrian Chen back to Brick | Pass. The role hierarchy inherits the front desk sharing rules. |
| Create an inquiry | Blocked, which is correct (Office Director is read only on inquiries) |
| Edit an instructor | Failed at first (fixed below) |
| Edit a lesson | Failed at first (fixed below) |

**Instructor edit failure:** the Instructor default is Public Read Only and no rule gave the Office Director write access. Object Edit permission isn't record access. Fix: an owner-based sharing rule on Instructor, records owned by All Internal Users → Office Director role → Read/Write. The Owner inherits it through the hierarchy. If a Music Director is added later, share to a public group instead of one role.

**Lesson edit failure:** the error was `insufficient access rights on entity: 01Iak00000EppGX`. The error referenced an ID starting with 01I, and Object Manager showed it was the Instructor object. Both failures had the same cause: the Office Director had Instructor object permissions but no record access, and saving a lesson needed write access to its Instructor parent because of the master-detail sharing setting.

After adding the Instructor sharing rule, the Office Director could edit instructors and create lessons.

### Front desk couldn't book lessons

FrontDesk Brick still couldn't save a new lesson. That confirmed the Lesson → Instructor master-detail **sharing setting was Read/Write**, which requires edit access on the parent instructor.

- Fix: Object Manager → Lesson → the Instructor master-detail field (`Instructor_External_Id__c`) → Sharing Setting → **Read Only**.
- Rejected alternative: give front desk edit access to instructor records. Booking a lesson shouldn't come with the right to edit instructor pay, hire date, or background check date.
- The Student side stays Read/Write on purpose. That's what keeps front desk booking limited to their own studio's students.

Tests, all passed:

- Office Director creates lessons.
- FrontDesk Brick creates lessons for Brick students.
- Negative test (screenshot): as FrontDesk Brick, creating a lesson for a Red Bank student (Rowan Carter, instructor Caroline Baker) is blocked with `insufficient access rights on cross-reference id: a07ak00001rZMpM`. The block comes from the Student side. "Cross-reference id" is the parent record the save couldn't write to, here a Student record. The earlier `01I` error pointed at an object, not a record.

### Owner (9/18)

As built: Student, Instructor, Lesson, and Enrollment Inquiry with Read/Create/Edit/Delete plus View All and Modify All. View All Fields off. All External ID fields and roll-up and formula fields read only.

Changes after the first draft:

1. Home Studio was editable, which would let the Owner misfile a student for every front desk sharing rule. Set to Read.
2. Location had object Read but field-level Edit on several fields, which does nothing and misleads the next admin. Resolved by giving the Owner full edit on Location, since opening or closing a studio is an owner decision.
3. View All Fields off, with field access granted explicitly, is correct. View All Fields would silently expose any new field.
4. Modify All ignores sharing, so the Owner's access doesn't depend on the role hierarchy. Intentional.
5. Delete plus Modify All is the most dangerous combination in the org. My accidental delete of every instructor (done as the admin, who has that power everywhere) shows why, and it's the reason Delete stays off every other permission set.

Verified as Owner: Home Studio not editable, full edit on Location, edits any student at any studio, no Setup access.

With that, the security model worked as designed for Front Desk (three studios), Marketing Director, Office Director, and Owner.

---

## 5. Minors' contact information

### Checking the data first

After designing a restriction for minors' contact info, I checked the data: 0 of 153 minors had a Student Phone, and 46 minors (ages 13 to 17) had a Student Email. All 27 adults had both. Phone was already adults-only in practice, so the per-record problem only existed for email.

The first design had three parts and was drafted before checking whether the data needed it. Checking the data first would have cut the scope right away.

Plan: a separate field for a minor's own email (`Minor Email`), hidden with field-level security from people who don't need it. Because FLS is per field, putting minors' email in its own field makes FLS work per record. The tradeoff is that a student turning 18 needs their email moved back.

### Birthday and a real Age formula

`Age__c` was a loaded Number field, so it never changes. A scheduled Flow couldn't detect a student turning 18. I added a Birthday field.

**Load error 13:**

| # | Object | Error | Cause | Fix |
|---|---|---|---|---|
| 13 | Student | `Id not specified in an update call` on all 183 rows | I ran Update, which needs the Salesforce record ID. The file only had External IDs. | 0 rows written. Re-ran as Upsert on `Student_External_Id__c`. |

Checks before re-running:

- Every birthday produced exactly the Age on record as of 2026-09-16. Nobody flipped between minor and adult, so Age could safely become a formula.
- STU-0045 has a blank birthday, which keeps the planted blank-age issue.
- `Status` was blank on all 183 rows again (the file had been re-saved through a spreadsheet), so I mapped only External ID and Birthday.
- STU-0067 and STU-0091 aren't in the org, so upsert would try to insert them and fail. 2 expected failures.
- Built-in test cases: STU-0032 Aubrey Wilson turns 18 on 2026-09-20, and STU-0015 Hazel Walker on 2026-10-02.

Age was used by Rule 2 and the guardian visibility rule, the same dependency trap as the Status migration. So I created a new formula field instead of changing the type in place:

```
YEAR(TODAY()) - YEAR(Birthday__c) - IF(DATE(YEAR(TODAY()), MONTH(Birthday__c), DAY(Birthday__c)) > TODAY(), 1, 0)
```

Edge case: a Feb 29 birthday makes `DATE(2027, 2, 29)` invalid, so the formula errors in non-leap years. There are no Feb 29 birthdays in the data, but a new student could have one.

### Record-triggered Flow: Minor Student Email

Record-triggered on Student, create or update. Entry: Age ≤ 17 and Student Email not blank. It copies the email into Minor Email and clears Student Email.

- I chose to move the email automatically instead of blocking entry with a validation rule. It's easier for front desk and gives the same security result.
- The first version used two Update Records elements on the triggering record, which means 2 extra saves, each re-running Student automation. I merged them into one element, which cut the extra saves to 1. A Fast Field Updates (before-save) Flow would remove the last one. I left it as an after-save Flow by choice.
- Active Flow versions can't be edited in place, so the change needed Save As New Version and then activating the new version.

### Two flows, not one

I considered one scheduled Flow handling both directions and decided on two flows, one per trigger:

- **Timing.** A scheduled Flow runs once a day, so a minor's email would sit in the general field, visible to everyone, until that night. The record-triggered Flow moves it the moment it's saved.
- **They're different events.** "A student turned 18" is time passing with no record change. A formula changing with `TODAY()` isn't a record update, so no record-triggered Flow fires on a birthday.
- **Combining them caused the bugs** in my first two scheduled drafts, because one filter had to cover two opposite groups.

A scheduled path based on Birthday wouldn't help existing records, since scheduled paths are only queued when a record is saved.

### Scheduled Flow: Update Minor Emails

Problems in the drafts:

- **Draft 1** filtered on `Student Email ≠ blank` AND `Birthday < 9/16/2008`. Born before that date means 18 or older, so it selected **only adults**: all 27 with an email. Its "Adult" branch set Student Email = Minor Email, and adults have no minor email, so the first run would have blanked every adult's email. The Recycle Bin can't restore overwritten field values. The Student Email filter also excluded the real targets (a minor turning 18 has their email in Minor Email), the hardcoded date was only right for one day, and a blank Age fell into the adult branch. It was never activated.
- **Draft 2** flipped the date filter, which removed the mass wipe, but still could never catch a student turning 18 and still had a blank-overwrite path.
- **V1 start conditions** used Age ≤ 17 instead of Age ≥ 18, and set "not blank" by leaving the value box empty instead of the explicit `Is Null = False`.

Final version:

- Schedule: daily. Object: Student.
- Start conditions: `Age ≥ 18` AND `Minor Email Is Null = False`.
- Action: Student Email ← Minor Email, then Minor Email ← blank.

Why it's safe:

- It filters on the field that defines the group (Minor Email), not a date, so adults never qualify.
- The source value can't be blank, so there's no blank-overwrite path.
- No back-and-forth with the record-triggered Flow: after the move, Age ≥ 18 fails that Flow's Age ≤ 17 condition.
- A blank Age (STU-0045) fails Age ≥ 18 and is skipped.

Accepted edge case: if someone types an email into Student Email for an 18-year-old before the nightly run, it gets overwritten by their old minor email.

The Flow was first scheduled for 3:45 PM. On Aubrey Wilson's birthday that would leave her Age at 18 from midnight to 3:45 PM, so Minor Email would be hidden and Student Email empty for about 15 hours. I moved the run to just after midnight.

### Backfilling existing minors' emails

A record-triggered Flow only acts on records saved after it's active, the same lesson as the name Flow. Existing records needed a save.

- **Attempt 1:** mass inline edit of 50 students, setting Name to "Adrian Chen." That saved the records and fired the Flow. Names survived only because the naming Flow reset Name on save. It depended on another automation undoing my edit, and it only covered 50 rows.
- **Attempt 2:** Data Loader upsert on `Student_External_Id__c` with a CSV of only minors. **153 updated, 1 error.** Every minor in the org was in the success file, 46 of them with an email. The error was STU-0091, which isn't in the org, so upsert tried to insert it and failed on required fields. Expected.
- Confirmed in the org: 0 minors with Student Email filled in. Statuses intact. (The success file showed "Item Updated" in the Status column, which is Data Loader's own status column, not the student field.)

### Field-level security test

Logged in as Marketing Director: on Aubrey Wilson (17 at the time), Minor Email wasn't visible and Student Email was blank. To prove it was field-level security and not just the page layout, I checked Report Builder: **Minor Email wasn't available there either.** FLS hides a field everywhere. A layout only hides it from the page.

That user also saw the default record page in the Sales app instead of the custom page. Apps weren't built yet (see section 8).

### Visibility rules and the minors' phone rule

Dynamic Forms on the Student page (UI only, not security, which is fine here because these fields should always be empty for minors):

- Minor Email: visible when Age ≤ 17
- Student Email: visible when Age ≥ 18
- Student Phone: visible when Age ≥ 18

Validation rule `Cannot_save_a_Minors_phone_number`:

```
Age_New__c <= 17 && NOT(ISBLANK(Student_Phone__c))
```

Existing data had 0 violations, so no records were blocked.

Problems with this setup:

- A blank Age hides all three contact fields (≤ 17 and ≥ 18 both fail). The same thing happens on New Student, since the formula isn't calculated until save. This led to making Birthday required (below).
- The error message should tell the user what to do (for example, enter the number in Guardian Phone) and should sit on the Student Phone field.
- This rule uses `&&` while others use `AND()`. One convention would be better.

### Parent/Guardian Pays

Requirement from my time at the academy: some students aged 18 to early 20s still have parents paying, so guardian info shouldn't disappear at 18.

My first draft showed Guardian First Name when Age ≤ 17, or Age = 0, or Guardian First Name isn't blank. Problems with that: front desk couldn't add a guardian to an adult, because the field only shows once it has a value; "Age = 0" is redundant; and if each guardian field checks its own value, a record could show some and hide others.

Built: a `Parent_Guardian_Pays__c` checkbox, visible when Age ≥ 18. All four guardian fields show when Age ≤ 17 OR the box is checked. It's explicit, editable, and reportable.

**Bug in the first version of its validation rule:**

```
Parent_Guardian_Pays__c && ISBLANK(Guardian_Email__c) || ISBLANK(Guardian_First_Name__c) || ISBLANK(Guardian_Last_Name__c) || ISBLANK(Guardian_Phone__c)
```

`&&` binds tighter than `||`, so this reads as "(Pays AND Email blank) OR First Name blank OR Last Name blank OR Phone blank." Any student with a blank guardian name or phone would fail, checkbox or not. That's all 27 adults, since none have guardian info. It's formula lesson 4 again.

Fixed:

```
AND(Parent_Guardian_Pays__c, OR(ISBLANK(Guardian_Email__c), ISBLANK(Guardian_First_Name__c), ISBLANK(Guardian_Last_Name__c), ISBLANK(Guardian_Phone__c)))
```

Regression tests on Fatima Jones (STU-0038, adult), all passed:

1. Box unchecked, no guardian: saved.
2. Box checked, guardian fields blank: blocked ("Review Guardian First Name").
3. Box checked, all four filled: saved.

The error sits on Guardian First Name, which is misleading when only phone or email is missing.

### Birthday required

- First I set `Birthday__c` to Required at the field level. A blank Birthday caused a blank Age, which broke visibility rules, validation rules, and both email flows. Requiring the source field fixes all of them at once.
- Problem: field-level Required applies to every save (UI, Data Loader, flows), so STU-0045 (no birthday) could no longer be saved by anything.
- Final: I unchecked field-level Required and added a validation rule, `Birthday_Required_on_new_Student`: `AND(ISBLANK(Birthday__c), ISNEW())`, with the error on Birthday. Legacy records stay editable. The real fix for STU-0045 is getting the birthday from the family, not inventing one.

### Incident: the turn-18 Flow erased Aubrey Wilson's email (9/20)

Aubrey Wilson (STU-0032) turned 18 on 9/20. The scheduled Flow ran, and **Minor Email was cleared while Student Email stayed blank.** Her email was gone from the org.

My first theory was that the two assignments inside the Update Records element were in the wrong order: Minor Email was cleared before Student Email copied it. The case against it: a single Update Records element might read every value from `$Record` as it was when the element started, which would make the order irrelevant. Other possibilities on the list: the record-triggered Flow firing afterward (that would move the email, not delete it), or Minor Email already being blank before 9/20.

**Blocker found while setting up the test:** Birthday didn't appear on the New Student form, even though it was on the page layout. With the new-record Birthday rule, that meant nobody could create a student through the UI at all, which breaks front desk's core job. Birthday was missing from the Dynamic Forms Lightning record page, which is what the New form actually uses. Fixed.

**Debug run** on a test student (18 today, Minor Email = test@emaill.com): **the order did matter.** My first theory was right.

- The element set `Minor_Email__c = ''` first, then `Student_Email__c = {!$Record.Minor_Email__c}`.
- Final values: Student Email blank, Minor Email blank. The second line read the already-cleared Minor Email. The debug line still showed "(test@emaill.com)" next to the reference, which was misleading.
- Ruled out: the record-triggered Flow (Age = 18, and the blank values appear inside this element before the save).
- This debug run was not in rollback mode, so the test student really was updated. That's fine for a test record, but real data should be debugged in rollback mode.
- Display quirk, not a bug: date fields show as 8:00 PM the previous day in debug output (midnight UTC shown in Eastern time).

**Fix (verified in debug with rollback on, 9/22):** I split the single update into **two Update Records elements**: "Change to Normal Field" (Student Email ← Minor Email), then "Blank Minor Field" (Minor Email ← blank). Final values: Student Email = test@emaill.com, Minor Email blank.

- Other fixes considered: reordering the rows (works, but the correctness depends on row order nobody can see), or storing Minor Email in a variable first. Splitting it makes the order visible on the canvas as separate steps.
- Tradeoff accepted: two saves per record instead of one, so validation rules and the record-triggered Flow run twice. I checked: after the first save, Age = 18, so the record-triggered Flow's Age ≤ 17 condition is false and it doesn't fire. Scheduled flows process records in batches, so the extra save doesn't matter at this size.

Cleanup: restored Aubrey's email from the source file, deleted the test student, and turned on **field history tracking for Student Email and Minor Email** (confirmed on 9/22). Before this there was no audit trail of what the Flow changed.

---

## 6. Reports and dashboards

### Planning (9/22)

I started with one report idea per persona, then rewrote them as audience, question, decision, and spec. What came out of reviewing the plan, which changed it:

- "Filter: student name" isn't a filter. A filter narrows which records count (status, date range, studio).
- A cancelled-lessons report can't tell who cancelled if Status only says "Cancelled." That was a data model gap.
- Lead source by volume rewards cheap leads. The better measure is conversion by source.
- Salesforce has no built-in goal field, so the target had to live somewhere, like gauge ranges. "Active students vs. last month" would need Reporting Snapshots, since reports show now, not history.
- Teacher pay should be paired with lesson counts, and belongs in a folder only the Office Director and Owner can open.
- Time to first response is the metric enrollment actually controls.

### Owner dashboard, first version (9/22)

Components: Total Students vs Capacity gauge (142 of 200), Total Monthly Revenue ($28,060), Active Students by Instrument (donut, 142), Active Students by Location (Red Bank 67, Brick 50, Toms River 25), Active Students table, Active Instructors table, Active Instructors by Location (43).

Two filter bugs that would fail silently:

1. The All Active Students report had **Show Me = "My students."** I owned every record, so it looked right for me and would return nothing for the Owner. Fix: All students. It has to be tested by logging in as the Owner.
2. The New Instructors report had **Created Date = Current FQ.** Every instructor was loaded on 9/14, so it would show 0 after October 1. Fix: remove that filter.

Missing from the review: revenue by studio, churn, pipeline, and a capacity number based on real data instead of a typed-in 200.

### Capacity and the roster trim

The first idea for real capacity was summing instructor Max Weekly Students. That gave about 830, and I caught that no three-studio school could deliver that. The real limit is rooms and teaching hours.

- Capacity = the smaller of instructor capacity and room-hour capacity. Room-hours = rooms × prime-time hours per week ÷ lesson length. Prime time is weekday afternoons and Saturday mornings.
- Biweekly students use half a weekly slot, so students and slots aren't 1 to 1 (Lesson Frequency carries this).
- It also exposed a bigger realism problem: 46 instructors for 181 students is about 4 students each. A real academy runs 20 to 30. The sample data was overstaffed.

**Roster trim, 43 active instructors → 15 (9/23).** I based it on demand:

- Weekly slot demand per studio and instrument, from active students only, with biweekly counted as 0.5. 143 active students = 120.5 weekly slots (Red Bank 53.5, Brick 45.0, Toms River 22.0).
- Every instrument with demand at a studio keeps at least one instructor there (two where demand is 6 or more slots), preferring instructors with future lessons and the most teaching history. Then capacity at least 1.3 × demand, then at least 3 instructors per studio.

| Studio | Kept | Weekly capacity | Demand | Instruments covered locally |
|---|---|---|---|---|
| Red Bank (LOC-001) | 5 | 86 | 53.5 | all but Cello |
| Brick (LOC-002) | 7 | 130 | 45.0 | all but Violin |
| Toms River (LOC-003) | 3 | 52 | 22.0 | Flute, Cello, Voice, Ukulele |

- Ratio went from 3.3 to 9.5 active students per instructor, which is realistic for part-time studio teachers.
- There's no Red Bank cello instructor anywhere in the roster, so Red Bank's cello slots are covered by instructors traveling from Brick or Toms River. That gap existed before the trim.
- Toms River's other instruments are covered by kept Red Bank and Brick instructors traveling.
- 24 future lessons pointed at instructors being deactivated. A reassignment file was generated (same studio and instrument, spread evenly across kept instructors, 0 unmatched), and I checked it before loading.
- **Both loads succeeded:** 46 instructor records updated (15 Active, 31 Inactive) and 24 future lessons reassigned. No errors.
- LSN-00003, the planted "inactive instructor on a future lesson" issue, was one of the reassigned lessons, so that planted issue is now resolved in the data.
- Historical lessons still point at the 31 deactivated instructors. That's realistic (teachers leave, their history stays), but any report filtered to active instructors drops that history. Filter on instructor status only when the question is about current staffing, never when it's about what happened.

**My capacity formula: `Practice_Rooms__c × 48`.** Open 6 hours × 6 days = 36 hours per room per week, ÷ 45-minute lessons = 48 slots. Problems with it: the actual average lesson is about 41 minutes (30 min × 436, 60 min × 203, 45 min × 190), so counting hours avoids a fixed lesson length. There's no turnaround time. The gauge compared students (142) to slots, which are different units. And it's a theoretical ceiling, while prime time is what's actually scarce.

In-org weekly slot demand: Red Bank 53.5, Brick 44.0, Toms River 22.0 (Brick is 1.0 below the source because STU-0067 was rejected). `locations.csv` had practice rooms of 8, 6, and 5. At 27 prime-time slots per room (weekday afternoons and Saturday mornings only, vs. 48 slots for all open hours), that's 25%, 27%, and 16% prime-time use, so either the school has too many rooms for 142 students or the room counts are off.

I dropped the capacity gauge in the next version and used a goal-based gauge instead.

### Owner dashboard, second version (9/23)

Added: Revenue Per Studio (Red Bank $13k, Brick $9.9k, Toms River $5.3k), Active vs Inactive Students (181: 142 Active, 23 Withdrawn, 16 Paused), a Current FQ Enrollment Inquiries funnel (38), and an "Active Students vs Q4 2026 Goals" gauge (142, bands at 120/160/200).

Problems with the second version:

1. **The funnel wasn't a funnel.** Segments were in alphabetical order, mixing pipeline stages with lost outcomes. Fixed: New → Contacted → Trial Scheduled → Converted → Unresponsive → Not Interested.
2. **Churn had no date.** 23 withdrawn students all-time says nothing about whether churn is rising. I needed a Withdrawn Date.
3. The dashboard shows revenue and Hourly Rate, so its folder needs to be limited, and it has to be tested as the Owner.
4. Revenue counts active students only, so paused students correctly add $0.

**Withdrawn Date.** None of the 23 withdrawn students had any lessons, so there was no activity to derive a real withdrawal date from. Options were: derive from last lesson (not possible here), leave blank and capture going forward, or generate plausible dates as sample data. They were generated as sample data, with rules: at least 60 days after enrollment, spread over about the last 24 months, slightly weighted toward recent. Result: 23 rows, 2024-10 to 2026-09, none before enrollment. In a real org you never invent dates. You derive them from evidence (last lesson, last invoice) and leave unknowns blank. This is sample data and the assumption is stated here.

- Field created, backfill loaded (23/23), and added to the record page with visibility Status = Withdrawn.
- Flow "Update Withdrawn Date": before-save, create or update, entry = Status changed AND Status = Withdrawn, action = Withdrawn Date ← `$System.OriginDateTime`.

Fixes to the Flow:

1. `$System.OriginDateTime` is GMT, so a Date saved after about 8 PM Eastern could land a day late. Changed to `$Flow.CurrentDate`, which follows the running user's time zone.
2. "Is Changed" is false on create, so the "created" half of the trigger never fired. Narrowed to update only.
3. Set the field to read only, since the Flow owns the value. (The backfill didn't trip the Flow, because Status never changed.)

Re-enrollment decision: when a student comes back, the date stays instead of being cleared, so the withdrawal history survives. Reports still see it, so churn metrics must filter on Status = Withdrawn. A second withdrawal overwrites the first, so the field means "most recent withdrawal." Full history would need a status-change child object, which is out of scope.

New component, "Enrolled Students vs Withdrawn this FQ" (Withdrawn Date = this quarter OR Enrollment Date = this quarter, grouped by Status): 10 enrolled vs. 4 withdrawn. Net growth is now visible.

**Owner login test passed:** logged in as the Owner, the dashboard rendered. One component showed "No data. Try refreshing" until refreshed, because dashboards cache results per running user.

**Funnel caveat:** at the time, Converted was larger than Trial Scheduled, because the chart groups by current status, not stages reached. A converted inquiry passed through Trial Scheduled but only counts at its final status. A true funnel needs "reached this stage or beyond" counts, which the data model doesn't track.

### Front desk: cancellations (9/24)

- Lesson Status was missing from the Lessons **report type** field layout. Custom report types have their own field list, and adding a field to the object doesn't add it to an existing report type. Fixed there.
- **"Who cancelled" solved with picklist values** instead of a new field: Status includes Cancelled by Student and No Show (vs. instructor-side cancellations). Simpler than a Cancelled By field, and one source of truth.

The problem with the first repeat-cancellation chart (a bar chart grouped by student): it was titled "repeat" but included students with one cancellation, and a bar chart of 100 names isn't something front desk can call from. Standard reports can't easily filter on a group's record count, so the cleaner option is a **roll-up summary on Student** counting lessons with Status = No Show or Cancelled by Student, then a report on students where that count is 2 or more. Roll-ups can't use relative dates, so it's all-time, and the quarterly report stays alongside it. (A weekly student also has twice the chances to cancel as a biweekly one.)

**Front Desk dashboard, first version (9/24):** This FQ Cancelled Lessons (table), by Location (Red Bank 23, Brick 16, Toms River 8), Repeat Students (table), Lessons Cancelled by Instructors (metric, 12).

Problems with the first version: "Repeat Students" listed one row per lesson, not per student. One dashboard with a **Location filter** beats three copies. The subtitle "0 is good, 25 is our max" is a job for conditional formatting. And makeups still owed were missing.

Results:

- The repeat-students table carries Cancellations, Guardian Phone, Student Phone, Lesson Frequency, Home Location, and Last Cancelled (a MAX roll-up). Login As Brick FrontDesk showed "Viewing as Brick FrontDesk," so it's a dynamic dashboard that runs as the viewer.
- **Bug: row duplication.** Nathan Ahmed and Miles Silva each appeared 3 times. The report used a Students with Lessons report type, which returns one row per lesson and repeats the student's roll-up values. Every column was a Student field, so I rebuilt it on the plain Students report type. Duplicates gone.
- **Location filter verified by Login As:** Brick FrontDesk with filter = Brick Studio sees 16 cancelled lessons (not 47) and only Brick repeat students. The instructor-cancelled metric drops from 12 to 5.

### Makeups

- Added a makeups component. Makeup Required = TRUE landed on exactly the instructor-cancelled lessons (12 this quarter, 35 all-time), so it showed the same records as "Cancelled by Instructors." The policy this encodes: instructor cancels → makeup owed. Student cancels or no-show → no makeup.
- Added a **Makeup Scheduled** checkbox to separate "owed" from "already booked." Backfill generated: 35 rows, 26 scheduled, weighted by age (older ones almost always handled, recent ones not yet).
- **Backfill loaded: 34 of 35 updated, 1 error.** The dashboard reads 12 makeups owed and 7 still outstanding this quarter (Brick 4, Toms River 2, Red Bank 1).
- The failure was **LSN-00621**, which I had already flagged because it had Makeup Required = TRUE but Status = Scheduled. Rule 1 rejected it: "The lesson can't be completed in future/scheduled for the past" (Scheduled, dated 3/11/2026).

A validation rule fires on every save, including a data fix. Records that were already invalid when the rule was created become frozen: you can't change any field until the bad one is fixed. So adding a validation rule to an org with existing data has a second step: report on the records that already break it and clean them up. Rule 1 was built in Phase 3, and this was the first time anything tried to write to that record.

Fix by hand: set Status to Cancelled by Instructor (consistent with Makeup Required = TRUE), then set Makeup Scheduled.

### Enrollment Director dashboard

Built 9/28: inquiries by stage, inquiry aging, converted inquiries by lead source, and average time to first response.

**The Average Response Time gauge read 0 as the Enrollment Director and 1.1 as me (9/29).**

Ruled out first, by checking rather than guessing: field-level security on `First_Response_Date__c` (visible for every profile), folder access (the report was in Public Reports), record access (the other three components showed 38 records as the Enrollment Director), and the formula (`Days from Inquiry to Response` is a row-level formula in the report, not a field).

Cause: the report's filter was **Show Me: My enrollment inquiries.** I owned every record in that report, so it showed 1.1 for me. The Enrollment Director owns none (they belong to me or the studio queues), so the report returned no rows and the average was 0. Fix: Show Me → All enrollment inquiries.

This was the second time. The Owner dashboard had the same "My students" bug on 9/22. Same default, same failure: a report that looks right to the admin because the admin owns everything in a dev org, and silently returns nothing to the person it was built for.

Rule I follow now: every dashboard gets opened as its intended user before I call it done.

---

## 7. Screen Flow: Inquiry to Student (9/26)

Launched from the Enrollment Inquiry record page: Get Records by `recordId` → decision on ConvertedStudentId (already converted?) → student details screen, pre-filled from the inquiry → age formula decision → guardian screen for minors → Create Student → Update Inquiry (Status = Converted, ConvertedStudentId = new student) → confirmation. Fault connectors on every data element.

Bugs found and fixed across five debug runs:

| Bug | Why it mattered |
|---|---|
| Get Records filtered on `Status ≠ Converted` instead of `Id = recordId` | Converted whichever inquiry sorted first, not the one the user clicked |
| Get Records stored only 5 fields | The decision used a field that was never loaded, causing "hasn't been set or assigned" |
| Decision pointed at an unpopulated variable (`InquiryVar`) | The already-converted check did nothing, so one inquiry could convert again and again |
| `Id = {!Record_Id.Id}`, a circular reference to the Get Records output | Returned zero records. Fixed with a proper `recordId` input variable. |
| Enrollment Date set to `$System.OriginDateTime` (gave 12/31/1899), then to Birthday | The user's entered date was thrown away twice before I read the mapping as a whole |
| Update Records filtered on Full_Name | Would stamp every inquiry sharing that name |
| Monthly Rate not collected | Converted students would show $0 on the revenue dashboard |

Tests passed: adult path, minor path shows the guardian screen, blank guardian fields blocked by Rule 2 with a readable message, run as Brick FrontDesk (permissions), and Name and Home Studio filled in by the downstream flows. (These tests missed a bug in the already-converted check. See "Pre-launch cleanup.")

Every bug above was in a debug run that finished without an error, so I stopped treating a clean run as a pass.

---

## 8. Apps and enrollment pipeline (9/26 to 9/28)

### Apps and Path

- Two Lightning apps: **Front Desk** (home page = "Next 7 Days of Lessons" dashboard with the Location filter, plus a link to the Cancellation dashboard) and **Owner** (home page = Owner dashboard). Verified with Login As for both.
- **Path** on Enrollment Inquiry: New → Contacted → Trial Scheduled → Converted → Unresponsive → Not Interested, with the Inquiry to Student Flow as a record page action.

### Queue routing

Three queues (Brick, Red Bank, Toms River Inquiry). A record-triggered Flow on Enrollment Inquiry create: decision on `Requested_Location__r.Name` → Get Records on **Group** (Type = Queue, DeveloperName = `<studio>_Inquiry`) → set OwnerId to the Group's Id. Verified on a real record, not just in debug.

- Bug caught in debug: the first version set OwnerId to `Group.OwnerId` (the queue's owner, my user) instead of `Group.Id` (the queue itself).
- Assignment rules only exist for Lead and Case, so routing a custom object takes a Flow and a Group query. Querying by DeveloperName keeps it portable across orgs instead of hardcoding a queue ID.
- **No backfill, on purpose.** Inquiries that existed before the Flow keep their current owner. Routing applies to new inquiries only.
- Tradeoffs, documented rather than built: three branches won't scale to a fourth studio (a queue name field on Location driving one Get Records would be cleaner), and the trigger is create-only so changing Requested Location doesn't re-route. An inquiry with no location goes down a "No Location" branch and stays with its creator.

### First Response Date (9/28)

A record-triggered Flow on **Task** (Status = Completed, WhatId not null) → Get Records on Enrollment Inquiry where Id = `$Record.WhatId` AND First Response Date is null → Update Records stamps today's date on that inquiry (if the Get found nothing, the update matches nothing) → decision: if Status is New, set it to Contacted. The field is read only on the layout.

- A task's Related To field (`WhatId`) can point to many kinds of records, so Flow can't reach the inquiry's fields through it directly. Looking up the inquiry by that Id works, and it also ignores tasks logged on other objects, since the lookup finds nothing.
- The Flow also moves Status to Contacted, but only when Status = New, so it can't knock an inquiry back from Trial Scheduled.
- Later fix (9/30): the entry condition now also requires `Auto_Generated_Followup__c = False`. See "Pre-launch cleanup."
- Verified live: logging a call on Genesis Rivera stamped 9/28/2026. A second logged call did not overwrite the date.

---

## 9. Scheduled follow-up Flow (9/29)

**Goal:** every morning, find enrollment inquiries with no first response after 3 or more days and create a follow-up task for the Enrollment Director, without creating a duplicate task every day.

### Final design: query the open tasks

Daily at 8:30 → **Get Open Tasks** (`Status != Completed` AND `Auto_Generated_Followup__c = True`) → **Task Loop** adds each task's WhatId to a text collection, `TaskedInquiryIds` → **Find Stale Inquiries** (First Response Date is null, Inquiry Date < `TODAY() - 3`, Id **Not In** `TaskedInquiryIds`) → **Get User** (Username and IsActive, first record) → **Enrollment Director Found?** decision confirms a user came back → **Inquiry Loop** builds one Task per inquiry into `Task_Collection` → one **Create Records** → fault path emails the admin.

An open auto-created task suppresses its inquiry. If a task is completed while First Response Date is still null, it drops out of the filter and the reminder comes back the next morning.

### Bugs found while building it

- Date logic reversed: `Inquiry_Date__c + 3 >= TODAY()` returns fresh inquiries. Correct: `Inquiry_Date__c` less than `TODAY() - 3`.
- Get Records stored only the first record instead of all records.
- Assignment variable and value swapped.
- Collection Sort mistaken for "add to a collection." It's a different element.
- Create Records inside the loop (one DML per record) instead of once after the loop with a collection.
- Description set three times with **Equals** (each overwrites the last) instead of Equals once, then **Add**.
- `$Flow.CurrentDateTime` assigned to a Date-only field.
- Dedupe, first try: assigned a record collection to a text variable and used **Does Not Equal**, which takes a single value. Only the last task in the loop would have been excluded. **Not In** is the only Flow filter operator that takes a collection, and for an Id field it needs a **Text** collection.
- Dedupe, second try: typed `{!Loop_2_WhatId}` by hand. Flow won't resolve a field path that wasn't picked from the resource picker. It has to be selected as `{!Loop_2.WhatId}`. The operator was also **Equals**, which overwrites the collection each time instead of adding to it.

### Rejected alternative: stamping the inquiry

The alternative was a `Last_Followup_Task_Date__c` field on Enrollment Inquiry, written when the task is created, with the Get filtering on it being null. No Task query, no loop, no collection.

I rejected it because of my business rule: if a task is marked Complete without anyone actually responding, that inquiry has been forgotten, and the reminder should come back. The Task-query design does that on its own (a completed task drops out of the filter, so a new task comes the next morning). A stamp field with Is Null would suppress the reminder forever, and a "more than 7 days ago" version would create a second task while the first is still open.

I deleted the half-built stamp version. Its mistakes: the Assignment sat between the Get and the loop, so it ran once instead of once per record; the record variable had no Id, so an update had nothing to target; and it added a made-up record to the Get's own output collection. The right pattern for "update every record I just queried" is to assign to the loop variable inside the loop (it already has the Id), add it to a separate collection, and update that collection after the loop.

### Don't dedupe on editable text

The dedupe first matched `Subject Equals "Follow up - no response in 3+ days"`. If someone reworded the Subject in the task without updating the Get filter, the Flow would create duplicates forever with no error. I replaced that with a custom `Auto_Generated_Followup__c` checkbox on Task, set in the Assignment and filtered on in the Get. The Subject is now free to change, and the flag is visible on the task.

### First debug run

- **Empty collection:** Get Open Tasks returned 0 records, so `TaskedInquiryIds` was empty. Find Stale Inquiries with `Id Not In` that empty collection still returned all 19 matching records. So `Not In` against an empty collection excludes nothing, which is what a first run needs. I didn't test whether `In` behaves the same way.
- **Failure:** `MALFORMED_ID: Assigned To ID: id value of incorrect type: Enrollment Director`. `TaskRecord.OwnerId` held the text "Enrollment Director" instead of a User Id. Same kind of mistake as the queue routing bug: a readable name where the platform wants an Id. Assignment elements don't type-check. The text sat in OwnerId through all 19 loop passes, and only the save rejected it.
- **Fix:** Get Records on User (`Username Equals <Enrollment Director username>` AND `IsActive = True`, first record), then assign `{!Get_Enrollment_Director.Id}`. IsActive matters because Salesforce rejects assigning a task to an inactive user. A Decision after the Get handles "no user found" instead of passing a null owner to the create.
- Not built: storing the assignee in a setting outside the Flow, so the Flow doesn't contain a username.
- **All or nothing:** 19 rows, one bad field value, zero tasks created. Everything a Flow saves in one run succeeds or fails together.
- **Second bug, found only in the debug log:** Description came out as `Sofia Thompson131ak000001XjDtAAKFlute`. `Requested_Location__c` is a lookup, so the raw Location record Id was being pasted into text a person has to read. Fix: reference `Requested_Location__r.Name` and use a single **Text Template** resource so the fields have separators.

### Fault handling

This run showed why a scheduled Flow needs it: everything failed, nothing was created, and nobody would have been told. A scheduled Flow has no user and no screen, so the fault connector on Create Records sends an email with `{!$Flow.FaultMessage}` to the admin. Screen flows can show a fault screen. Scheduled flows have to notify someone, or the failure is silent.

### Inverted decision found before activation

I walked through every element. Fixed since the first pass: Assigned To now uses the User Id from Get User, the `TaskSubtype` row was deleted, Description uses the Location Name, an orphaned Update Records element was deleted, a Decision was added after Get User, and seven orphaned resources were deleted.

A review of the Decision found it inverted. Its only outcome was "Enrollment Director Returns Blank" with `User ID Is Null = True`, and that outcome led to the loop, while the Default Outcome led to End. When the user was found, the Flow went to Default and ended without doing anything. When the user was missing, it ran the loop and built 19 tasks with no owner.

Fix: flip the operator to `Is Null = False` and rename the outcome "Enrollment Director Found." The existing connector is then correct.

With the decision inverted, a debug run would finish with no error and create zero records, and it would look like a pass. So I check the record count after a run, not just whether it errored.

Final fixes: fault path added on Create Records, and the Interested Instrument row dropped so the Description has one separator for one join.

### Remaining warning: sending email from a scheduled Flow

Flow Builder showed 0 errors and 1 warning: "Because the Automated Process User has no email address, this flow can't send emails for actions or errors."

Schedule-triggered flows run as the Default Workflow User. For the Send Email action in a scheduled Flow, Process Automation Settings needs an **Automated Process User Email Address**, which is set up from an org-wide email address. Without it, the fault email is wired up but will never send.

### Test runs

- **Debug run (rollback mode):** full clean pass. Get Open Tasks returned 0, `Not In` excluded nothing, Find Stale Inquiries returned 19, Get User returned a real User Id, the Decision took "Enrollment Director Found," the inquiry loop built 19 tasks, and Create Records staged 19 rows in 1 DML statement. Description read `Sofia Thompson, Red Bank Studio`. The debug run was in rollback mode ("any changes to add, delete, or modify records were rolled back"), so nothing was actually created. That proves the build, not the behavior. The dedupe can't be tested until the tasks exist.
- **Live run (rollback off):** 19 tasks created. On the Sofia Thompson inquiry, the task "Follow up - no response in 3+ days" was on the activity timeline, due Today, with "Enrollment Director has an upcoming task." The debug output had shown the due date as "September 27, 2026 at 8:00 PM." The stored date was correct, so that was only a display artifact (midnight UTC shown in Eastern time). I checked it instead of assuming.
- **Dedupe run:** against the 19 existing tasks, Get Open Tasks returned 19, the task loop put all 19 WhatIds into `TaskedInquiryIds`, Find Stale Inquiries returned 0, the inquiry loop ran zero times, and Create Records received nothing. The first real run created 19 tasks. The next created 0.

Other checks:

- The empty-collection run still reported `DML statements: 1 out of 150, DML rows: 1 out of 10000`, which could mean a blank task was written. The Task list had 22 records: the 19 follow-ups plus 3 earlier logged calls. No junk record, so that counter is a debug output artifact.
- On a created task: Assigned To = Enrollment Director, Status = Not Started, Due Date = 9/28/2026 (matches `$Flow.CurrentDate`), Comments = `Tyler Wilson, Red Bank Studio` (Comments is `Description` in the API). The `Auto_Generated_Followup__c` flag was confirmed by behavior, since the next run's Get filtered on it and found all 19.
- Created By showed 6:33 PM for a run at 9:33 PM, because my display time zone is three hours off the org's. Scheduled flows run on the org's time zone.

I kept the 19 tasks as demo data.

---

## 10. Pre-launch cleanup (9/29 to 10/1)

- **Report and dashboard folders restricted.** Reports moved out of Public Reports into three folders that match the personas: Owner, Front Desk, and Enrollment Director. The Owner folder, which holds the revenue reports, is shared with the owner (View) and my admin user (Manage). After moving everything, I opened every dashboard as its intended user to confirm each component still had data.
- **Test data deleted.** Removed the students and guardian data created while testing the screen Flow, and reset inquiries that had been flipped to Converted during testing.
- **Marketing Director role assigned**, so the role hierarchy in the org matches the diagram.
- **Fault email set up.** Added and verified an org-wide email address and set it as the Automated Process User Email Address, so a failed scheduled Flow emails the error.
- **Final check against the README.** Recounted records, permission sets, validation rules, and dashboard components in the org before publishing. The inquiry count in my notes was out of date (the org has 139, not 38). Confirmed Unique is on for the External ID fields.
- **Screen Flow bug: double conversion.** The already-converted check used "Converted Student Does not equal [blank]". A debug run on an already-converted inquiry showed it didn't route to the "Already Converted" screen, so the record could be converted a second time. Fix: the condition is now `Converted Student Is Null = True` (outcome "Not Converted" goes to the conversion screens), and the default outcome, "Already Converted," goes to a screen that tells staff the inquiry is already a student. Re-tested in debug after the change.
- **Screen Flow: guardian contact saved for adults.** Create Student copied the inquiry's email and phone into both the student and guardian fields for every student. A 46-year-old test student got his own email and phone as his guardian's, and for a child the parent's email landed in Student Email (and then Minor Email). Fix: an Assignment on each branch prefills the right Student fields from the inquiry ("Prefill Student Contact" for adults, "Prefill Guardian Contact" for minors), the screens are bound to those Student fields so staff can correct them, and Create Student reads everything from the Student variable. Minors never get a student phone, so `Cannot_save_a_Minors_phone_number` still passes.
  - Why not a default value: screen fields bound to a record variable have no Default Value setting. They show whatever the variable already holds, so the Assignment before the screen does that job.
  - Testing: Debug's rollback mode isn't offered for screen Flows, so I added a temporary Roll Back Records element right before the confirmation screen, tested an adult and a minor, then removed it before activating. The first time I placed it after the screen, which didn't work: the screen had already saved the records.
- **Inquiry names.** Enrollment Inquiry records were named by their record ID, so IDs showed up in the Enrollment Director dashboard, on follow-up tasks (Related To), and in Recent Records. I added a record-triggered Flow, `Update Inquiry Name`, then backfilled the existing records. It runs on create or update, before save (Fast Field Updates), and sets Name to a formula: `{!$Record.First_Name__c} + " " + {!$Record.Last_Name__c}`. The entry condition is `Name <>` that same formula, so it only runs when the name is actually wrong.
  - Why a Flow formula instead of the Full Name formula field: formula fields aren't recalculated before save, so on a brand-new record Full Name is still blank when the Flow runs.
  - My first version left out the space and would have named records "LeoOrtiz". I caught it and fixed it in V4. Every inquiry name checked afterward.
  - **Load error 14:** my first backfill was an upsert of the original `inquiries.csv`. All 140 rows failed with `Inquiry_External_Id__c not specified`, because the CSV header has no `__c` and auto-map skipped it, so the match field was never mapped. Nothing was written, which was lucky: that file is the original sample data (140 rows vs. 139 in the org, plus the planted `LOC-009`), so a successful run would have overwritten values I'd since changed and inserted a record. The right file for a backfill is an export from the org (Id plus External ID), run as an Update.
- **Two Flows working against each other.** The First Response Flow fired on *any* completed task on an inquiry, including the follow-up task the scheduled Flow creates. So completing a follow-up task stamped First Response Date even if nobody had called, and the reminder never came back. That broke the exact rule I rejected the simpler follow-up design for. Fix: the First Response Flow now also requires `Auto_Generated_Followup__c = False`, so only real logged activity counts. Tested both ways: completing a follow-up task leaves First Response Date blank, and logging a call stamps it.
- **Birthday required in the screen Flow.** Birthday wasn't required on the first screen, so a blank birthday got all the way to Create Student and failed the new-student Birthday rule with a raw error. It's required on the screen now, so staff get told before they click Next.
- **Default element names replaced.** Loop 1/2, Assignment 1/2, and Decision 1 in the follow-up Flow, and "Copy 2 of Fault" and "Copy 4 of Fault" in the screen Flow, now say what they do, and so do the First Response Flow's elements (Get Inquiry, Update Inquiry, "Is the Inquiry New?", and the two fault elements). The naming Flow on Instructor now runs on create as well as update, so a new instructor gets a real name right away.
- **Dashboards kept from emptying out.** The enrollment and owner reports were filtered to Current FQ, so on October 1 they would have dropped to almost nothing. They're now set to the last 365 days. I kept the "Current FQ" titles because that's the window the business would actually watch, and the README explains it. Also added a Conversion Rate by Lead Source chart (row-level formula: 100 if Converted, else 0, averaged by lead source) and filtered out inquiries with no lead source.
- **Cancellation reports locked to one studio.** The cancellation reports had two locked "Location equals Brick Studio" filters, so the dashboard showed only Brick's cancellations whichever studio was selected. Removed them and rechecked the dashboard with the filter on All and on Brick.
- **Lessons scheduled through March 2027.** The lesson data ended on 10/7. I exported active students and lessons, generated 499 future lessons from them (each student's preferred day, home studio, primary instrument, and current instructor if still active and qualified), checked them, and loaded them with Data Loader after a 10-row test.
  - The test failed one row: James Moore, Rule 3. He was still the planted instructor with no background check date. A school shouldn't book lessons with a teacher who hasn't passed a background check, so I gave him a check date, which resolves that planted issue (see section 1). The date is made up, like the rest of the sample data. In a real org the check would have to happen before he's booked. The rest loaded with no errors.
- **Duplicate rule on Student.** Matching rule: First Name, Last Name, and either Guardian Email or Student Email, all Exact, with blanks never counting as a match. Duplicate rule: Allow with an alert and a report on create and edit, bypassing sharing so a match at another studio still shows up.
  - Why email and not just name: siblings share a last name and guardian email, and two different kids can share a name. Requiring the first name and an email keeps both from being flagged. Minors always have a guardian email (Rule 2), and an adult's own email is in Student Email. An adult with no email on file can't be matched.
  - Tested on the New Student form with two existing duplicate pairs: Sofia Johnson matched both existing records on guardian email, and Logan Harris matched both "Logan Harris" and "LOGAN Harris" on student email, so Exact matching ignores case. Neither test record was saved.

---

## 11. Known limitations

These match the "What I'd do differently" section of the README, plus smaller items I documented instead of fixing.

- **Inquiries are a custom object, not the standard Lead.** Leads come with built-in conversion, assignment rules, and web-to-lead. The tradeoff is that Lead conversion creates an Account and Contact (and optionally an Opportunity), and this school's customers are Students.
- **Follow-up tasks go to one named user.** Assigning them to a queue would remove the dependency on one person.
- **Routing has three hardcoded branches** and only runs on create. A fourth studio needs a Flow change, and changing an inquiry's location doesn't re-route it. The decision also branches on the Location's Name, so renaming a studio would break routing. The Home Studio Flow uses the Location External ID for exactly that reason, and routing should too.
- **The funnel shows current status, not stages reached.** A converted inquiry counts only as Converted, so the chart can widen where a real funnel wouldn't.
- **Existing duplicates aren't merged.** The duplicate rule only checks a record when it's saved, so the planted duplicate students (STU-0181/0182/0183) are still in the org. Custom objects have no merge, so cleaning them up means moving their lessons and deleting the extra records.
- **Roll-up summaries can't filter by relative dates,** so repeat-cancellation counts are all-time. The quarterly view is in a report.
- **Report folders are shared with individual users.** With a handful of users it works the same, but a larger org should share by role.
- **Withdrawn Date means "most recent withdrawal"** and survives re-enrollment, so churn reports have to filter on Status = Withdrawn.
- **Misleading API names:** Lesson's relationship fields are named `Student_External_Id__c`, `Instructor_External_Id__c`, and `Location_External_Id__c`, but they're master-detail and lookup fields. Home Studio's API name is `Home_Picklist__c`, and the Age formula is `Age_New__c`. Renaming them now would mean updating every Flow and report that uses them.
- **Rule 3 fires on system saves.** A roll-up recalculation on a noncompliant instructor runs the rule and blocks the lesson save. It should only fire when the record is new or when Active or Background Check Date changes.
- **The Age formula fails on Feb 29 birthdays** in non-leap years. The same logic is also in the screen Flow's age formula, so both would need the fix.
- **Rule 4 doesn't catch a 0-minute completed lesson.**
- **Student transfers are one-way** for the sending studio. A mistaken transfer has to be undone by the receiving studio, the Office Director, or the Owner.
- **STU-0009** still needs a birthday and guardian phone and email from the family. Rule 2 blocks edits to that record until then. Rule 2's error message still says "under the age of 18" and doesn't mention a missing birthday.
- **Screen Flow polish:** fault screens show the raw `FIELD_CUSTOM_VALIDATION_EXCEPTION:` prefix.
- **`Practice_Rooms__c` and the capacity fields are unused** since I dropped the capacity gauge.
