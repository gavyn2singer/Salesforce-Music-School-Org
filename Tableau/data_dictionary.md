# Data dictionary

This file describes the columns in `SQLExport_fixed.csv` and the calculated fields and the parameter used in the dashboard. The data is fictional. It comes from a Salesforce developer org that I filled with made up music school inquiries.

The CSV has one row for each inquiry, 140 rows in total, plus a header row. The columns come from the query in `Inquiries.sql`.

## Columns

| Column | Type | What it means | Example | How it is made |
|---|---|---|---|---|
| inquiry_id | text | The Salesforce record ID for one inquiry. | a09ak00002KAZXvAAP | `Inquiries.Id` |
| studio | text | The studio the family asked for. | Brick Studio | Studio name from `Locations.Name`, joined on `Requested_Location__c`. A left join keeps inquiries that have no studio. |
| lead_source | text | How the family first heard about us. | Google Search | `Lead_Source__c`. A blank value becomes `Unknown`. |
| status | text | The current status of the inquiry. | Trial Scheduled | `Status__c`. Values are New, Contacted, Trial Scheduled, Converted, Not Interested, and Unresponsive. |
| inquiry_date | date | The day the inquiry came in. | 2026-03-21 | `Inquiry_Date__c` |
| inquiry_month | text | The year and month of the inquiry. | 2026-03 | `inquiry_date` formatted as YYYY-MM with `strftime`. |
| days_to_respond | number | Days from the inquiry to the first reply. Decimal values are allowed. | 5.0 | First reply date minus inquiry date. Blank when nobody replied. Negative values come from bad source dates. |
| finished | Yes or No | Yes when the status is Converted, Not Interested, or Unresponsive. | Yes | Case statement on `status`. The dashboard shows this column as "decided". |
| days_open | number | Days the inquiry has been open. Only for inquiries still in play. | 231.0 | 2026-10-26 minus inquiry date, for New, Contacted, and Trial Scheduled. Blank for all other statuses. |
| response_bucket | text | How fast the first reply came. | 3. 3-7 days | Case statement on the reply gap in days. Values are 1. Same day, 2. 1-2 days, 3. 3-7 days, 4. 8+ days, 5. Never contacted, and 6. Data issue. The numbers keep the labels in order when sorted. |
| outcome_group | text | A simple outcome label for each inquiry. | Lost | Values are Converted, Lost, Never contacted, and Open. Lost means Not Interested or Unresponsive after a reply. Never contacted means no reply at all. |

The dashboard uses friendlier names for some of these values. Response buckets show as Same day, 1 to 2 days, 3 to 7 days, 8 or more days, and No reply. Outcome groups show as Converted, Lost, Never contacted, and Still open.

## Calculated fields

These fields are built in Tableau from the columns above. The field names used in Tableau are not listed here. Each one is described by its formula.

Close rate is converted inquiries divided by decided inquiries. Decided means converted or lost. The overall close rate is 34.5%, which is 41 converted out of 119 decided. The tooltip on the close rate mark explains this in plain words.

Expected enrollments is the number of open inquiries for a lead source, times that source's close rate. The dashboard adds these up to about 7.2 for all open inquiries. Walk-In has the highest expected value at 1.7. The numbers are rounded.

## Parameter

Day limit for an open inquiry is a parameter on the dashboard. The default value is 220 days. Lead sources with open inquiries older than this limit show in orange on the pipeline chart. Change the value to change which sources turn orange.

## Data notes

Two inquiries have reply dates before the inquiry date. They are labeled "6. Data issue" and are left out of the response speed chart. One inquiry has no lead source. It is labeled Unknown and is left out of the lead source chart. The data stops on October 26, 2026.
