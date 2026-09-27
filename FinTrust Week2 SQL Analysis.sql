-- =============================================================================
-- FinTrust_Week2_SQL_Analysis.sql
-- AnalystLab Africa | Week 2 | Data Analytics Track
-- Environment: DuckDB
-- Data: cleaned FinTrust datasets (synthetic, educational). 
-- NOTE: Risk_Review_Flag is a synthetic label, NOT a real fraud decision.
-- Analysis rule: value questions use Transaction_Status = 'Successful' only.
-- =============================================================================

-- STEP 0: LOAD DATA (DuckDB) ---------------------------------------------------
-- The two cleaned CSVs come from the Excel cleaning stage (Device_Type and
-- Location blanks replaced with 'Unknown'; Customer_ID header added).
-- Yes/No columns are forced to VARCHAR so DuckDB does not turn them into booleans.

CREATE OR REPLACE TABLE customers AS
SELECT * FROM read_csv('FinTrust_Customer_Clean.csv', header = true);

CREATE OR REPLACE TABLE transactions AS
SELECT * FROM read_csv('FinTrust_Transaction_Clean.csv', header = true,
       types = {'International_Transaction': 'VARCHAR', 'Risk_Review_Flag': 'VARCHAR'});


-- =============================================================================
-- Q0. BUSINESS QUESTION: Data relationship check: do the two datasets join cleanly?
-- =============================================================================
SELECT
    (SELECT COUNT(*) FROM customers)    AS customer_records,
    (SELECT COUNT(*) FROM transactions) AS transaction_records,
    (SELECT COUNT(*) FROM transactions t
      WHERE NOT EXISTS (SELECT 1 FROM customers c
                         WHERE c.Customer_ID = t.Customer_ID)) AS orphan_transactions,
    (SELECT COUNT(*) FROM customers c
      WHERE NOT EXISTS (SELECT 1 FROM transactions t
                         WHERE t.Customer_ID = c.Customer_ID)) AS customers_without_transactions;

-- RESULT:
--    customer_records  transaction_records  orphan_transactions  customers_without_transactions
--                1500                12000                    0                               0
--
-- BUSINESS INTERPRETATION:
--   Every transaction matches a customer and every customer has at least one transaction (0
--   orphans, 0 inactive customers), so joins on Customer_ID are safe and no records are lost.
--   Customers average exactly 8.0 transactions each.

-- =============================================================================
-- Q1. BUSINESS QUESTION: What share of transactions succeed, fail, reverse or stay pending, and how much value sits in each status?
-- =============================================================================
SELECT
    Transaction_Status,
    COUNT(*)                                            AS txn_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_txns,
    ROUND(SUM(Amount_NGN), 0)                           AS total_value_ngn
FROM transactions
GROUP BY Transaction_Status
ORDER BY txn_count DESC;

-- RESULT:
--   Transaction_Status  txn_count  pct_of_txns  total_value_ngn
--           Successful      10856        90.47        510807441
--               Failed        630         5.25         24825751
--             Reversed        326         2.72         15626118
--              Pending        188         1.57          9218044
--
-- BUSINESS INTERPRETATION:
--   90.5% of transactions succeed. Failed, reversed and pending transactions make up 9.5% of
--   volume and about NGN 49.7M (roughly 8.9% of all value). Failed plus reversed alone is 8.0%
--   of volume, which is the main workload for customer support. All value analysis below uses
--   Successful transactions only, so that failed or reversed money is not counted as real
--   activity.

-- =============================================================================
-- Q2. BUSINESS QUESTION: Which transaction types generate the most value, and how skewed are the amounts?
-- =============================================================================
SELECT
    Transaction_Type,
    COUNT(*)                   AS txn_count,
    ROUND(SUM(Amount_NGN), 0)  AS total_value_ngn,
    ROUND(AVG(Amount_NGN), 0)  AS avg_value_ngn,
    ROUND(MEDIAN(Amount_NGN), 0) AS median_value_ngn
FROM transactions
WHERE Transaction_Status = 'Successful'
GROUP BY Transaction_Type
ORDER BY total_value_ngn DESC;

-- RESULT:
--   Transaction_Type  txn_count  total_value_ngn  avg_value_ngn  median_value_ngn
--           Transfer       3213        218365428          67963             15126
--            Deposit       1211        119531761          98705             21753
--      Card Purchase       2745         77957947          28400              7558
--    Cash Withdrawal       1290         61396432          47594             17784
--       Bill Payment       1336         24971374          18691              7026
--       Airtime/Data       1061          8584499           8091              2464
--
-- BUSINESS INTERPRETATION:
--   Transfers are FinTrust's core product: 42.7% of successful value (NGN 218M) from 3,213
--   transactions. Deposits have the highest average (NGN 98.7k) but a median of only NGN
--   21.8k, and every type has a mean roughly 2.7 to 4.5 times its median. A few very large
--   transactions pull the averages up, so medians should be used when describing a typical
--   transaction. Airtime/Data is high volume but only 1.7% of value.

-- =============================================================================
-- Q3. BUSINESS QUESTION: Which channels carry the most traffic, and which fail most often?
-- =============================================================================
SELECT
    Channel,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN Transaction_Status = 'Successful' THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Transaction_Status = 'Failed'     THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct
FROM transactions
GROUP BY Channel
ORDER BY txn_count DESC;

-- RESULT:
--      Channel  txn_count  success_rate_pct  failure_rate_pct
--   Mobile App       5102             89.75              5.80
--          POS       2393             90.85              5.22
--          Web       1869             90.85              4.71
--          ATM       1747             91.70              4.18
--         USSD        889             90.33              5.40
--
-- BUSINESS INTERPRETATION:
--   The Mobile App carries 42.5% of all transactions but has the lowest success rate (89.75%)
--   and highest failure rate (5.80%), so it accounts for about 47% of all failed transactions.
--   ATM performs best (91.70%). The gap is only about 2 percentage points, so it is a signal
--   to investigate rather than proof of a fault. Because Mobile App volume is so large,
--   improving it would remove the most failures.

-- =============================================================================
-- Q4. BUSINESS QUESTION: Do customer segments differ in transaction behaviour?
-- =============================================================================
SELECT
    c.Customer_Segment,
    COUNT(DISTINCT c.Customer_ID)                                   AS customers,
    COUNT(*)                                                        AS txn_count,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT c.Customer_ID), 1)        AS txns_per_customer,
    ROUND(SUM(t.Amount_NGN) / COUNT(DISTINCT c.Customer_ID), 0)     AS value_per_customer_ngn
FROM transactions t
JOIN customers c ON c.Customer_ID = t.Customer_ID
WHERE t.Transaction_Status = 'Successful'
GROUP BY c.Customer_Segment
ORDER BY value_per_customer_ngn DESC;

-- RESULT:
--   Customer_Segment  customers  txn_count  txns_per_customer  value_per_customer_ngn
--                SME        216       1553                7.2                  354889
--            Student        278       2044                7.4                  350292
--            Premium        295       2148                7.3                  342538
--           Everyday        711       5111                7.2                  331535
--
-- BUSINESS INTERPRETATION:
--   Not much. Value per customer ranges only from NGN 331.5k (Everyday) to NGN 354.9k (SME),
--   and transactions per customer sit between 7.2 and 7.4. The current segments do not explain
--   how customers behave. FinTrust may get more from a behaviour-based segmentation (recency,
--   frequency, value) than from the existing labels.

-- =============================================================================
-- Q5. BUSINESS QUESTION: Which transaction types are sent for risk review most often?
-- =============================================================================
SELECT
    Transaction_Type,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS risk_review_rate_pct
FROM transactions
GROUP BY Transaction_Type
ORDER BY risk_review_rate_pct DESC;

-- RESULT:
--   Transaction_Type  txn_count  risk_review_rate_pct
--           Transfer       3549                 28.49
--    Cash Withdrawal       1430                 25.31
--            Deposit       1328                 16.19
--       Airtime/Data       1185                 15.19
--      Card Purchase       3033                 13.02
--       Bill Payment       1475                 12.81
--
-- BUSINESS INTERPRETATION:
--   Transfers (28.5%) and cash withdrawals (25.3%) are reviewed about twice as often as bill
--   payments (12.8%) or card purchases (13.0%). Review effort is concentrated in transactions
--   where money leaves the customer's control. Note that Risk_Review_Flag is synthetic and is
--   not a fraud determination.

-- =============================================================================
-- Q6. BUSINESS QUESTION: Are international transactions treated differently?
-- =============================================================================
SELECT
    International_Transaction AS international,
    COUNT(*)                  AS txn_count,
    ROUND(AVG(Amount_NGN), 0) AS avg_value_ngn,
    ROUND(100.0 * SUM(CASE WHEN Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2)      AS risk_review_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Transaction_Status = 'Successful' THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_rate_pct
FROM transactions
GROUP BY International_Transaction
ORDER BY International_Transaction;

-- RESULT:
--   international  txn_count  avg_value_ngn  risk_review_rate_pct  success_rate_pct
--              No      11520          46917                 18.88             90.36
--             Yes        480          41658                 36.88             93.13
--
-- BUSINESS INTERPRETATION:
--   International transactions are only 4% of volume but are flagged for review at 36.9%,
--   almost double the domestic rate (18.9%). Their average value is actually lower (NGN 41.7k
--   vs NGN 46.9k), so size alone does not explain the difference. Their success rate is higher
--   (93.1%). International status appears to be its own driver of review.

-- =============================================================================
-- Q7. BUSINESS QUESTION: How does the risk-review rate change with transaction size?
-- =============================================================================
SELECT
    CASE WHEN Amount_NGN <   1000 THEN '1: under 1k'
         WHEN Amount_NGN <  10000 THEN '2: 1k-10k'
         WHEN Amount_NGN <  50000 THEN '3: 10k-50k'
         WHEN Amount_NGN < 100000 THEN '4: 50k-100k'
         WHEN Amount_NGN < 250000 THEN '5: 100k-250k'
         ELSE                          '6: 250k+' END AS amount_band,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS risk_review_rate_pct
FROM transactions
GROUP BY amount_band
ORDER BY amount_band;

-- RESULT:
--    amount_band  txn_count  risk_review_rate_pct
--    1: under 1k       1487                 16.01
--      2: 1k-10k       4460                 18.21
--     3: 10k-50k       3110                 17.81
--    4: 50k-100k       1214                 18.95
--   5: 100k-250k       1225                 25.47
--       6: 250k+        504                 40.87
--
-- BUSINESS INTERPRETATION:
--   The rate is fairly flat (16% to 19%) up to NGN 100k, then rises to 25.5% for NGN 100k to
--   250k and 40.9% above NGN 250k. There is a clear threshold effect, so amount is likely a
--   strong driver of the flag. A review policy that targets large transactions would
--   concentrate attention where the rate is highest.

-- =============================================================================
-- Q8. BUSINESS QUESTION: How does transaction activity change month to month?
-- =============================================================================
SELECT
    strftime(Transaction_DateTime, '%Y-%m')                                        AS month,
    COUNT(*)                                                                       AS txn_count,
    COUNT(DISTINCT CAST(Transaction_DateTime AS DATE))                             AS active_days,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT CAST(Transaction_DateTime AS DATE)), 0)  AS txns_per_day,
    ROUND(AVG(CASE WHEN Transaction_Status = 'Successful' THEN Amount_NGN END), 0) AS avg_successful_ngn
FROM transactions
GROUP BY month
ORDER BY month;

-- RESULT:
--     month  txn_count  active_days  txns_per_day  avg_successful_ngn
--   2026-01       4133           31           133               46040
--   2026-02       3734           28           133               47191
--   2026-03       4133           31           133               47934
--
-- BUSINESS INTERPRETATION:
--   Monthly counts are 4,133, 3,734 and 4,133, but February has fewer days. Per day, volume is
--   a constant 133 transactions in every month, and average successful value rises only
--   slightly (NGN 46.0k to NGN 47.9k, +4.1%). There is no growth or seasonality to report over
--   these 3 months. The timestamps are evenly spaced, which is a limitation of the synthetic
--   data (see the Python notebook).

-- =============================================================================
-- Q9. BUSINESS QUESTION: Do dormant and restricted accounts behave differently from active ones?
-- =============================================================================
SELECT
    c.Account_Status,
    COUNT(DISTINCT c.Customer_ID)                             AS customers,
    COUNT(*)                                                  AS txn_count,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT c.Customer_ID), 1)  AS txns_per_customer
FROM transactions t
JOIN customers c ON c.Customer_ID = t.Customer_ID
GROUP BY c.Account_Status
ORDER BY txn_count DESC;

-- RESULT:
--   Account_Status  customers  txn_count  txns_per_customer
--           Active       1367      10910                8.0
--          Dormant        107        866                8.1
--       Restricted         26        224                8.6
--
-- BUSINESS INTERPRETATION:
--   They do not. Dormant customers average 8.1 transactions each and Restricted customers 8.6,
--   compared with 8.0 for Active. If 'Dormant' meant inactive, these customers should transact
--   far less. Either the status field is stale or the status is not enforced. This is a data
--   governance question to raise with FinTrust.

-- =============================================================================
-- Q10. BUSINESS QUESTION: Do customers use the channel they say they prefer?
-- =============================================================================
SELECT
    c.Preferred_Channel,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN t.Channel = c.Preferred_Channel THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_txns_on_preferred_channel
FROM transactions t
JOIN customers c ON c.Customer_ID = t.Customer_ID
GROUP BY c.Preferred_Channel
ORDER BY txn_count DESC;

-- RESULT:
--   Preferred_Channel  txn_count  pct_txns_on_preferred_channel
--          Mobile App       7377                          42.46
--                 Web       2908                          15.92
--                USSD       1715                           7.52
--
-- BUSINESS INTERPRETATION:
--   No visible link. Only 42.5% of transactions by Mobile-App-preferring customers happen on
--   the Mobile App, 15.9% of Web-preferring customers' transactions use Web, and 7.5% of USSD-
--   preferring customers' transactions use USSD. These figures are almost identical to the
--   overall channel shares (42.5%, 15.6%, 7.4%), so stated preference has no effect on actual
--   channel use. Preferred_Channel is not a reliable basis for channel targeting.

-- =============================================================================
-- Q11. BUSINESS QUESTION: How concentrated is transaction value among customers?
-- =============================================================================
WITH customer_value AS (
    SELECT Customer_ID, SUM(Amount_NGN) AS value_ngn
    FROM transactions
    WHERE Transaction_Status = 'Successful'
    GROUP BY Customer_ID
),
ranked AS (
    SELECT *, NTILE(10) OVER (ORDER BY value_ngn DESC) AS decile
    FROM customer_value
)
SELECT
    decile,
    COUNT(*)                                                  AS customers,
    ROUND(SUM(value_ngn), 0)                                  AS value_ngn,
    ROUND(100.0 * SUM(value_ngn) / SUM(SUM(value_ngn)) OVER (), 2) AS pct_of_total_value
FROM ranked
GROUP BY decile
ORDER BY decile;

-- RESULT:
--    decile  customers  value_ngn  pct_of_total_value
--         1        150  137779283               26.97
--         2        150   92236278               18.06
--         3        150   72783874               14.25
--         4        150   58354823               11.42
--         5        150   47329025                9.27
--         6        150   37366089                7.32
--         7        150   28147535                5.51
--         8        150   19987176                3.91
--         9        150   12306473                2.41
--        10        150    4516888                0.88
--
-- BUSINESS INTERPRETATION:
--   Moderately concentrated. The top 10% of customers (150) produce 27.0% of successful value,
--   the top 30% produce 59.3%, and the bottom half produce only 20.0%. Protecting and growing
--   the top deciles matters most for revenue, while the bottom decile (0.9%) is nearly
--   inactive.
