-- Enrollment Director dashboard: one row per inquiry
-- The as-of date is fixed to the export date, so the numbers do not change between runs.
-- The finished column is shown as "decided" on the dashboard. Yes means the inquiry reached an end: Converted, Not Interested, or Unresponsive.

SELECT
  Inquiries.Id                                   AS inquiry_id,
  Locations.Name                                 AS studio,
  COALESCE(Inquiries.Lead_Source__c, 'Unknown')  AS lead_source,  -- A blank lead source shows as Unknown.
  Inquiries.Status__c                            AS status,
  Inquiries.Inquiry_Date__c                      AS inquiry_date,
  strftime('%Y-%m', Inquiries.Inquiry_Date__c)   AS inquiry_month,

  -- NULL means nobody ever replied. This is expected.
  julianday(Inquiries.First_Response_Date__c)
    - julianday(Inquiries.Inquiry_Date__c)       AS days_to_respond,

  CASE WHEN Inquiries.Status__c IN ('Converted', 'Not Interested', 'Unresponsive')
       THEN 'Yes' ELSE 'No' END                  AS finished,

  -- Days open only for inquiries that are still open.
  CASE WHEN Inquiries.Status__c IN ('New', 'Contacted', 'Trial Scheduled')
       THEN julianday('2026-10-26') - julianday(Inquiries.Inquiry_Date__c)
       ELSE NULL END                             AS days_open,

  -- Response time bucket. Check NULL first, because NULL fails every < test.
  -- A negative number means the reply date is before the inquiry date (bad source data). It gets its own bucket.
  -- Labels start with numbers so Tableau sorts them in order.
  CASE
    WHEN Inquiries.First_Response_Date__c IS NULL
         THEN '5. Never contacted'
    WHEN julianday(Inquiries.First_Response_Date__c) - julianday(Inquiries.Inquiry_Date__c) < 0
         THEN '6. Data issue'
    WHEN julianday(Inquiries.First_Response_Date__c) - julianday(Inquiries.Inquiry_Date__c) < 1
         THEN '1. Same day'
    WHEN julianday(Inquiries.First_Response_Date__c) - julianday(Inquiries.Inquiry_Date__c) < 3
         THEN '2. 1-2 days'
    WHEN julianday(Inquiries.First_Response_Date__c) - julianday(Inquiries.Inquiry_Date__c) < 8
         THEN '3. 3-7 days'
    ELSE '4. 8+ days'
  END AS response_bucket,

  -- Outcome group (Q1). A lost inquiry with no reply counts as Never contacted,
  -- since the director can fix that by replying sooner.
  CASE
    WHEN Inquiries.Status__c = 'Converted'                          THEN 'Converted'
    WHEN Inquiries.First_Response_Date__c IS NULL                   THEN 'Never contacted'
    WHEN Inquiries.Status__c IN ('Not Interested', 'Unresponsive')  THEN 'Lost'
    ELSE 'Open'
  END AS outcome_group

FROM Inquiries
LEFT JOIN Locations
  ON Inquiries.Requested_Location__c = Locations.Id;  -- LEFT JOIN keeps inquiries that have no studio.