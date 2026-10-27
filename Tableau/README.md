# Enrollment Director dashboard

Fictional data from a Salesforce music school org. Updated Oct 26, 2026.

Live dashboard: https://public.tableau.com/views/EnrollmentDirectorDashboard/EnrollmentDirectorDashboard

## What this is

I built this project to practice Salesforce admin and reporting work. The data is fictional. I made a Salesforce developer org, filled it with 140 fake inquiries from a music school with a few studios, and wrote one SQL query to pull the inquiries into a flat table. I exported that table to a CSV file and built a Tableau dashboard on top of it.

The flow is Salesforce, then SQL, then CSV, then Tableau.

## Three questions

1. Does reply speed change the outcome?
2. Which lead sources close best?
3. What is in the open pipeline, and what should we expect from it?

## Key findings

- 140 inquiries. 119 are decided (converted or lost). 41 converted, a close rate of 34.5%.
- 19 inquiries were never contacted.
- Inquiries that got a reply within a week converted 33 to 38% of the time.
- When the first reply took 8 or more days, 3 of 11 converted (27%). That is a small sample, so read it with care.
- Website Form has the best close rate at 53.8%. Referral has the lowest at 17.6%.
- 21 inquiries are still open. They have been open for 42 to 263 days. 19 are New, 1 is Contacted, and 1 is Trial Scheduled.
- Based on past close rates, about 7.2 enrollments are expected from the open inquiries. Walk-In has the most, at 1.7.
- May had the most inquiries (23). September (5) and October (1) look low only because the data stops on Oct 26, 2026.

## How to read the dashboard

The dashboard has 5 sheets:

- Summary: total inquiries, close rate, and never contacted.
- How fast we replied and what happened: reply speed and outcomes.
- Inquiries by month.
- Close rate by lead source.
- Open inquiries and expected enrollments: the pipeline.

Close rate means converted inquiries divided by decided inquiries (converted or lost).

The Day limit control sets how long an open inquiry can wait before it counts as "over the limit." The default is 220 days. On the pipeline sheet, orange bars mark lead sources that have open inquiries older than the limit.

## Tools

- Salesforce developer org, with fake data
- SQL, written in SQLite style
- Tableau Desktop to build the dashboard, and Tableau Public to share it

## Data notes

- 2 inquiries have reply dates before the inquiry date. They are left out of the reply speed chart.
- 1 inquiry has no lead source. It shows as Unknown and is left out of the lead source chart.
- The data stops on Oct 26, 2026.
- Inquiries with no reply show as "Never contacted" in the SQL.

## How to re-run

1. Run Inquiries.sql against the Inquiries and Locations tables in Salesforce or another SQL tool.
2. Save the result as a CSV file with the same 11 columns.
3. Open the Tableau workbook and replace its data source with the new CSV.
4. Check that the Summary sheet numbers match what you expect.

## Files

- README.md: this file.
- Inquiries.sql: the one SQL query that builds the table, with comments.
- SQLExport_fixed.csv: the 140 inquiry rows and 11 columns that the query produced.
- data_dictionary.md: what each column means, and how the calculated fields work.
- screenshots/: screenshots (dashboard and sheet images).
- publish_steps.md: how to publish the dashboard to Tableau Public and upload this folder to GitHub.
- resume_line.md: resume and LinkedIn wording for this project.
