-- =============================================================================
-- FinTrust_Week2_SQL_Analysis_Advanced.sql
-- AnalystLab Africa | Week 2 | Data Analytics Track | Section A: Q0-Q11, Section B: advanced Q12-Q24
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


-- #############################################################################
-- SECTION B: ADVANCED ANALYTICAL QUESTIONS (Q12 - Q24)
-- #############################################################################
-- Section A (Q0-Q11) described what is happening. Section B asks the harder
-- follow-up questions a sceptical manager would raise:
--   * Is a gap real, or could it be chance?            (Q13, Q17)
--   * Is a pattern explained by something else?        (Q12, Q15)
--   * Could a simple, explainable rule do the job?     (Q14)
--   * Who are the customers behind the numbers?        (Q16, Q17, Q22, Q23)
--   * Where is operational money stuck or lost?        (Q18, Q19)
--   * Does timing or sequence matter?                  (Q20, Q21)
--   * What is the one-page summary for management?     (Q24)
-- Conventions are unchanged: value questions use Successful transactions only,
-- and Risk_Review_Flag is a synthetic label, not a fraud decision.
-- RESULT blocks are filled in after running each query on the cleaned data.
-- #############################################################################


-- =============================================================================
-- Q12. BUSINESS QUESTION: Which channel and transaction-type combinations fail
--      far more often than the platform average?
-- WHY IT MATTERS: Q3 showed Mobile App failing slightly more often overall, but
--      a channel-level average can hide one weak combination (for example a
--      single transaction type on a single channel). Fixing a specific route is
--      cheaper than fixing a whole channel.
-- =============================================================================
WITH combo AS (
    SELECT
        Channel,
        Transaction_Type,
        COUNT(*) AS txn_count,
        SUM(CASE WHEN Transaction_Status = 'Failed' THEN 1 ELSE 0 END) AS failed_txns
    FROM transactions
    GROUP BY Channel, Transaction_Type
),
platform AS (
    SELECT 1.0 * SUM(failed_txns) / SUM(txn_count) AS platform_failure_rate
    FROM combo
)
SELECT
    c.Channel,
    c.Transaction_Type,
    c.txn_count,
    c.failed_txns,
    ROUND(100.0 * c.failed_txns / c.txn_count, 2)                       AS failure_rate_pct,
    ROUND(100.0 * p.platform_failure_rate, 2)                           AS platform_rate_pct,
    ROUND((1.0 * c.failed_txns / c.txn_count) / p.platform_failure_rate, 2) AS failure_lift
FROM combo c
CROSS JOIN platform p
WHERE c.txn_count >= 100          -- ignore thin cells that swing on a handful of cases
ORDER BY failure_lift DESC
LIMIT 10;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [Read failure_lift as a multiple of the platform average: 1.00 is normal,
--    1.30 means 30% more failures than expected. Name the top two or three
--    routes, state their volume so the reader can judge materiality, and say
--    whether the weak routes sit mainly on Mobile App. If no combination is
--    far above 1.00, say so: the Q3 gap is then spread evenly and is not a
--    single broken route.]


-- =============================================================================
-- Q13. BUSINESS QUESTION: Is the Mobile App's higher failure rate statistically
--      meaningful, or is it within normal random variation?
-- WHY IT MATTERS: Q3 called the gap "a signal to investigate rather than proof".
--      This query tests it. A two-proportion z-test compares Mobile App with all
--      other channels combined, and a 95% confidence interval shows the likely
--      size of the gap in percentage points.
-- =============================================================================
WITH grp AS (
    SELECT
        CASE WHEN Channel = 'Mobile App' THEN 'mobile' ELSE 'other' END AS grp_name,
        COUNT(*) AS n,
        SUM(CASE WHEN Transaction_Status = 'Failed' THEN 1 ELSE 0 END) AS failures
    FROM transactions
    GROUP BY 1
),
pair AS (
    SELECT
        m.n AS n_mobile,  m.failures AS f_mobile,
        o.n AS n_other,   o.failures AS f_other,
        1.0 * m.failures / m.n                         AS p_mobile,
        1.0 * o.failures / o.n                         AS p_other,
        1.0 * (m.failures + o.failures) / (m.n + o.n)  AS p_pool
    FROM grp m
    JOIN grp o ON m.grp_name = 'mobile' AND o.grp_name = 'other'
),
test AS (
    SELECT *,
        (p_mobile - p_other) / SQRT(p_pool * (1 - p_pool) * (1.0 / n_mobile + 1.0 / n_other)) AS z,
        SQRT(p_mobile * (1 - p_mobile) / n_mobile + p_other * (1 - p_other) / n_other)        AS se
    FROM pair
)
SELECT
    ROUND(100 * p_mobile, 2)                                AS mobile_failure_pct,
    ROUND(100 * p_other, 2)                                 AS other_failure_pct,
    ROUND(100 * (p_mobile - p_other), 2)                    AS gap_pp,
    ROUND(100 * (p_mobile - p_other - 1.96 * se), 2)        AS ci95_low_pp,
    ROUND(100 * (p_mobile - p_other + 1.96 * se), 2)        AS ci95_high_pp,
    ROUND(z, 2)                                             AS z_score,
    CASE WHEN ABS(z) >= 1.96 THEN 'Significant at 5%'
         ELSE 'Not significant at 5%' END                   AS conclusion
FROM test;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [If |z| is below 1.96, or the confidence interval includes 0, the gap could
--    be chance and the honest message is "no evidence that Mobile App is
--    worse". If it is significant, report the gap with its interval, and note
--    that statistical significance is not the same as business importance: a
--    significant gap of under 1 percentage point may not justify engineering
--    work.]


-- =============================================================================
-- Q14. BUSINESS QUESTION: Could a simple, explainable rule capture most of the
--      transactions that end up flagged for risk review?
-- WHY IT MATTERS: Q5 to Q7 found that amount, international status and
--      transaction type all relate to the flag. Management usually prefers a
--      rule it can explain over a black box. This query builds the rule in three
--      steps and measures each against the flag:
--        precision = of the transactions the rule selects, how many are flagged
--        recall    = of all flagged transactions, how many the rule catches
--        lift      = precision divided by the overall flag rate (1.0 = no better
--                    than reviewing at random)
-- =============================================================================
WITH scored AS (
    SELECT
        CASE WHEN Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END AS flagged,
        CASE WHEN Amount_NGN >= 100000 THEN 1 ELSE 0 END AS r1,
        CASE WHEN Amount_NGN >= 100000
               OR International_Transaction = 'Yes' THEN 1 ELSE 0 END AS r2,
        CASE WHEN Amount_NGN >= 100000
               OR International_Transaction = 'Yes'
               OR Transaction_Type IN ('Transfer', 'Cash Withdrawal') THEN 1 ELSE 0 END AS r3
    FROM transactions
)
SELECT 'R1: amount >= NGN 100k' AS rule,
       SUM(r1) AS txns_selected,
       ROUND(100.0 * SUM(r1) / COUNT(*), 1)                          AS pct_of_volume,
       ROUND(100.0 * SUM(r1 * flagged) / SUM(r1), 1)                 AS precision_pct,
       ROUND(100.0 * SUM(r1 * flagged) / SUM(flagged), 1)            AS recall_pct,
       ROUND((1.0 * SUM(r1 * flagged) / SUM(r1)) / (1.0 * SUM(flagged) / COUNT(*)), 2) AS lift
FROM scored
UNION ALL
SELECT 'R2: R1 or international',
       SUM(r2),
       ROUND(100.0 * SUM(r2) / COUNT(*), 1),
       ROUND(100.0 * SUM(r2 * flagged) / SUM(r2), 1),
       ROUND(100.0 * SUM(r2 * flagged) / SUM(flagged), 1),
       ROUND((1.0 * SUM(r2 * flagged) / SUM(r2)) / (1.0 * SUM(flagged) / COUNT(*)), 2)
FROM scored
UNION ALL
SELECT 'R3: R2 or Transfer/Cash Withdrawal',
       SUM(r3),
       ROUND(100.0 * SUM(r3) / COUNT(*), 1),
       ROUND(100.0 * SUM(r3 * flagged) / SUM(r3), 1),
       ROUND(100.0 * SUM(r3 * flagged) / SUM(flagged), 1),
       ROUND((1.0 * SUM(r3 * flagged) / SUM(r3)) / (1.0 * SUM(flagged) / COUNT(*)), 2)
FROM scored;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [Each added condition should raise recall but dilute precision, because the
--    rule selects more of the volume. State the trade-off in plain terms, for
--    example "R3 reviews X% of all transactions to catch Y% of flagged ones".
--    If the best rule still has modest lift, the flag depends on factors these
--    three fields do not capture. That is a useful handover note for the Data
--    Science track, which will model the flag formally.]


-- =============================================================================
-- Q15. BUSINESS QUESTION: Is the higher review rate on international
--      transactions real, or simply because of which transaction types they are?
-- WHY IT MATTERS: Q5 shows review rates differ a lot by type, and Q6 shows
--      international transactions are flagged more. If international traffic is
--      mostly Transfers, the "international effect" might just be a Transfer
--      effect. Comparing like with like inside each type removes that doubt.
-- =============================================================================
WITH by_type AS (
    SELECT
        Transaction_Type,
        SUM(CASE WHEN International_Transaction = 'Yes' THEN 1 ELSE 0 END) AS intl_txns,
        SUM(CASE WHEN International_Transaction = 'No'  THEN 1 ELSE 0 END) AS dom_txns,
        SUM(CASE WHEN International_Transaction = 'Yes' AND Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) AS intl_flagged,
        SUM(CASE WHEN International_Transaction = 'No'  AND Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) AS dom_flagged
    FROM transactions
    GROUP BY Transaction_Type
)
SELECT
    Transaction_Type,
    intl_txns,
    ROUND(100.0 * intl_flagged / NULLIF(intl_txns, 0), 2)  AS intl_review_rate_pct,
    ROUND(100.0 * dom_flagged  / NULLIF(dom_txns, 0), 2)   AS domestic_review_rate_pct,
    ROUND((1.0 * intl_flagged / NULLIF(intl_txns, 0))
        / NULLIF(1.0 * dom_flagged / NULLIF(dom_txns, 0), 0), 2) AS intl_to_domestic_ratio
FROM by_type
ORDER BY Transaction_Type;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [If the ratio stays clearly above 1.0 in every type, international status
--    is an independent driver and the Q6 conclusion holds. If it is near 1.0 in
--    most types, the Q6 gap came from transaction mix. Check intl_txns before
--    trusting any single row: a ratio built on fewer than about 50 transactions
--    is unstable and should be described as indicative only.]


-- =============================================================================
-- Q16. BUSINESS QUESTION: Can behaviour-based (RFM) segments describe customers
--      better than the existing Customer_Segment labels?
-- WHY IT MATTERS: Q4 found almost no difference between the current segments.
--      RFM scores customers on Recency (days since last successful
--      transaction), Frequency (number of successful transactions) and
--      Monetary value (total successful value), each in quartiles 1 to 4
--      (4 = best). Customer_ID is used as a tie-breaker so quartile assignment
--      is repeatable, because many customers share the same frequency.
-- =============================================================================
CREATE OR REPLACE VIEW customer_rfm AS
WITH ref AS (
    SELECT MAX(Transaction_DateTime) AS ref_dt FROM transactions
),
cust AS (
    SELECT
        t.Customer_ID,
        DATE_DIFF('day', MAX(t.Transaction_DateTime), (SELECT ref_dt FROM ref)) AS recency_days,
        COUNT(*)           AS frequency,
        SUM(t.Amount_NGN)  AS monetary
    FROM transactions t
    WHERE t.Transaction_Status = 'Successful'
    GROUP BY t.Customer_ID
),
scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY recency_days DESC, Customer_ID) AS r_score,
        NTILE(4) OVER (ORDER BY frequency, Customer_ID)         AS f_score,
        NTILE(4) OVER (ORDER BY monetary, Customer_ID)          AS m_score
    FROM cust
)
SELECT *,
    CASE WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
         WHEN r_score <= 2 AND m_score >= 3                  THEN 'At-risk high value'
         WHEN f_score <= 2 AND m_score <= 2                  THEN 'Low engagement'
         ELSE 'Core customers' END AS rfm_segment
FROM scored;

-- Q16a. Size and value of each behavioural segment
SELECT
    rfm_segment,
    COUNT(*)                                                       AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS pct_customers,
    ROUND(AVG(frequency), 1)                                       AS avg_txns,
    ROUND(AVG(monetary), 0)                                        AS avg_value_ngn,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)   AS pct_of_value
FROM customer_rfm
GROUP BY rfm_segment
ORDER BY avg_value_ngn DESC;

-- Q16b. Do the old labels line up with the new behavioural segments?
SELECT
    c.Customer_Segment,
    ROUND(100.0 * SUM(CASE WHEN r.rfm_segment = 'Champions'          THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_champions,
    ROUND(100.0 * SUM(CASE WHEN r.rfm_segment = 'At-risk high value' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_at_risk_high_value,
    ROUND(100.0 * SUM(CASE WHEN r.rfm_segment = 'Low engagement'     THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_low_engagement,
    COUNT(*) AS customers
FROM customer_rfm r
JOIN customers c ON c.Customer_ID = r.Customer_ID
GROUP BY c.Customer_Segment
ORDER BY c.Customer_Segment;

-- RESULT:
--   [paste both outputs here]
--
-- BUSINESS INTERPRETATION:
--   [State how much value the Champions and At-risk high value groups hold. If
--    every Customer_Segment shows roughly the same percentage in each RFM
--    segment (Q16b), the existing labels carry no behavioural information and
--    RFM is the better basis for targeting. Mention that recency has limited
--    spread here because the data covers only three months.]


-- =============================================================================
-- Q17. BUSINESS QUESTION: Are failed transactions concentrated in a small group
--      of customers, or spread randomly across the base?
-- WHY IT MATTERS: If a few customers fail repeatedly, the fix is targeted
--      outreach and support. If failures are random, the fix is in the platform.
--      The test compares the number of customers with 3 or more failures against
--      what pure chance would produce, using a binomial calculation at the
--      observed platform failure rate and an approximate 8 transactions per
--      customer (from Q0).
-- =============================================================================
-- Q17a. Distribution of failures per customer
WITH per_customer AS (
    SELECT Customer_ID,
           SUM(CASE WHEN Transaction_Status = 'Failed' THEN 1 ELSE 0 END) AS failed_txns
    FROM transactions
    GROUP BY Customer_ID
)
SELECT
    failed_txns,
    COUNT(*)                                                    AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_customers,
    failed_txns * COUNT(*)                                      AS failed_txns_total
FROM per_customer
GROUP BY failed_txns
ORDER BY failed_txns;

-- Q17b. Observed vs expected number of customers with 3+ failures
WITH per_customer AS (
    SELECT Customer_ID,
           SUM(CASE WHEN Transaction_Status = 'Failed' THEN 1 ELSE 0 END) AS failed_txns
    FROM transactions
    GROUP BY Customer_ID
),
rate AS (
    SELECT 1.0 * SUM(CASE WHEN Transaction_Status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*) AS p
    FROM transactions
)
SELECT
    COUNT(*)                                                    AS customers,
    SUM(CASE WHEN failed_txns >= 3 THEN 1 ELSE 0 END)           AS observed_3plus,
    ROUND(COUNT(*) * (1 - POW(1 - p, 8)
                        - 8  * p * POW(1 - p, 7)
                        - 28 * POW(p, 2) * POW(1 - p, 6)), 1)   AS expected_3plus_if_random
FROM per_customer
CROSS JOIN rate;

-- RESULT:
--   [paste both outputs here]
--
-- BUSINESS INTERPRETATION:
--   [If observed_3plus is close to expected_3plus_if_random, failures behave
--    like independent events and there is no "problem customer" group: the
--    cause is platform-wide. If observed is clearly higher, a subset of
--    customers is failing repeatedly and should be profiled (segment, channel,
--    account status) and contacted by support.]


-- =============================================================================
-- Q18. BUSINESS QUESTION: How long have pending transactions been waiting, and
--      how much customer money is in limbo?
-- WHY IT MATTERS: A pending transaction is normal for seconds or minutes. One
--      that is days old points to a stuck settlement or reconciliation backlog,
--      and customers will contact support about it. Age is measured against the
--      latest timestamp in the data, not today's date.
-- =============================================================================
WITH ref AS (
    SELECT MAX(Transaction_DateTime) AS ref_dt FROM transactions
)
SELECT
    CASE WHEN DATE_DIFF('day', t.Transaction_DateTime, r.ref_dt) <= 1  THEN '1: 0-1 days'
         WHEN DATE_DIFF('day', t.Transaction_DateTime, r.ref_dt) <= 7  THEN '2: 2-7 days'
         WHEN DATE_DIFF('day', t.Transaction_DateTime, r.ref_dt) <= 30 THEN '3: 8-30 days'
         ELSE                                                               '4: over 30 days' END AS pending_age,
    COUNT(*)                                      AS pending_txns,
    ROUND(SUM(t.Amount_NGN), 0)                   AS value_in_limbo_ngn,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_pending
FROM transactions t
CROSS JOIN ref r
WHERE t.Transaction_Status = 'Pending'
GROUP BY pending_age
ORDER BY pending_age;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [Report how many pending transactions are older than a week and the value
--    attached. These are the cases operations should clear first. If pending
--    items are spread evenly across all ages, status appears unrelated to
--    timing, which is a limitation of the synthetic data and should be stated
--    rather than hidden.]


-- =============================================================================
-- Q19. BUSINESS QUESTION: How much attempted value does FinTrust fail to
--      complete, and which transaction types lose the most?
-- WHY IT MATTERS: Q1 counted unsuccessful transactions. Management also needs
--      the value, because a failed NGN 400k transfer hurts more than a failed
--      NGN 500 airtime top-up. This ranks types by value that did not complete
--      and shows whether failures skew toward larger amounts.
-- =============================================================================
SELECT
    Transaction_Type,
    ROUND(SUM(Amount_NGN), 0)                                                          AS attempted_value_ngn,
    ROUND(SUM(CASE WHEN Transaction_Status <> 'Successful' THEN Amount_NGN END), 0)    AS not_completed_ngn,
    ROUND(100.0 * SUM(CASE WHEN Transaction_Status <> 'Successful' THEN Amount_NGN END)
                / SUM(Amount_NGN), 2)                                                  AS pct_value_not_completed,
    ROUND(AVG(CASE WHEN Transaction_Status = 'Failed'     THEN Amount_NGN END), 0)     AS avg_failed_ngn,
    ROUND(AVG(CASE WHEN Transaction_Status = 'Successful' THEN Amount_NGN END), 0)     AS avg_successful_ngn
FROM transactions
GROUP BY Transaction_Type
ORDER BY not_completed_ngn DESC;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [Identify the type with the largest value not completed and compare its
--    percentage with the platform figure from Q1 (about 8.9%). If avg_failed is
--    close to avg_successful, failures are not size-driven. If failed averages
--    are noticeably higher or lower, say so, since it changes whether the fix
--    is a limit or timeout issue or a general reliability issue.]


-- =============================================================================
-- Q20. BUSINESS QUESTION: Do failure and review rates change by time of day?
-- WHY IT MATTERS: Night-time spikes in failures can indicate batch-processing
--      windows or maintenance, and unusual-hour activity is a common review
--      trigger. Q8 showed volumes are evenly spread across days, so hour of
--      day is checked separately.
-- =============================================================================
SELECT
    CASE WHEN EXTRACT(hour FROM Transaction_DateTime) < 6  THEN '1: 00:00-05:59 night'
         WHEN EXTRACT(hour FROM Transaction_DateTime) < 12 THEN '2: 06:00-11:59 morning'
         WHEN EXTRACT(hour FROM Transaction_DateTime) < 18 THEN '3: 12:00-17:59 afternoon'
         ELSE                                                    '4: 18:00-23:59 evening' END AS time_band,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN Transaction_Status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Risk_Review_Flag = 'Yes'      THEN 1 ELSE 0 END) / COUNT(*), 2) AS risk_review_rate_pct,
    ROUND(AVG(Amount_NGN), 0) AS avg_value_ngn
FROM transactions
GROUP BY time_band
ORDER BY time_band;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [Compare the four bands. Differences of a few tenths of a percentage point
--    on roughly 3,000 transactions per band are within normal noise; only
--    report a time effect if a band stands out clearly. If rates are flat,
--    conclude that time of day is not a useful risk or reliability signal in
--    this dataset.]


-- =============================================================================
-- Q21. BUSINESS QUESTION: Are transactions that follow another transaction from
--      the same customer within a short time flagged more often?
-- WHY IT MATTERS: Rapid repeat activity (velocity) is one of the most common
--      real-world review triggers. LAG() finds the gap since each customer's
--      previous transaction so the flag rate can be compared across gap sizes.
-- =============================================================================
WITH seq AS (
    SELECT
        Customer_ID,
        Risk_Review_Flag,
        DATE_DIFF('minute',
                  LAG(Transaction_DateTime) OVER (PARTITION BY Customer_ID ORDER BY Transaction_DateTime),
                  Transaction_DateTime) AS mins_since_prev
    FROM transactions
)
SELECT
    CASE WHEN mins_since_prev IS NULL    THEN '0: first transaction'
         WHEN mins_since_prev <= 60      THEN '1: within 1 hour'
         WHEN mins_since_prev <= 1440    THEN '2: within 24 hours'
         WHEN mins_since_prev <= 10080   THEN '3: within 7 days'
         ELSE                                 '4: over 7 days' END AS gap_since_previous,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS risk_review_rate_pct
FROM seq
GROUP BY gap_since_previous
ORDER BY gap_since_previous;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [If short gaps carry a higher review rate, a velocity feature (time since
--    previous transaction) is worth passing to the Data Science track. If the
--    rate is flat, say that velocity shows no relationship with the flag here.
--    Check txn_count for the shortest band first; with about 8 transactions per
--    customer over three months, very few gaps may fall within an hour.]


-- =============================================================================
-- Q22. BUSINESS QUESTION: How much value and review activity passes through
--      Dormant and Restricted accounts?
-- WHY IT MATTERS: Q9 showed these accounts transact as often as Active ones.
--      That is a governance concern. This puts a naira value and a risk profile
--      on the exposure so the issue can be prioritised.
-- =============================================================================
SELECT
    c.Account_Status,
    COUNT(DISTINCT c.Customer_ID)                                                       AS customers,
    SUM(CASE WHEN t.Transaction_Status = 'Successful' THEN 1 ELSE 0 END)                AS successful_txns,
    ROUND(SUM(CASE WHEN t.Transaction_Status = 'Successful' THEN t.Amount_NGN END), 0)  AS successful_value_ngn,
    ROUND(100.0 * SUM(CASE WHEN t.Transaction_Status = 'Successful' THEN t.Amount_NGN END)
                / SUM(SUM(CASE WHEN t.Transaction_Status = 'Successful' THEN t.Amount_NGN END)) OVER (), 2) AS pct_of_value,
    ROUND(100.0 * SUM(CASE WHEN t.Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2)            AS risk_review_rate_pct
FROM transactions t
JOIN customers c ON c.Customer_ID = t.Customer_ID
GROUP BY c.Account_Status
ORDER BY successful_value_ngn DESC;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [State the naira value and share of total moved by Dormant and Restricted
--    accounts. Note whether their review rate is higher than Active, since a
--    restricted account should in principle be reviewed more, not less. Because
--    the transaction dates are not compared with the date the status was set,
--    the status may have changed after these transactions; treat this as a
--    question for FinTrust's data owners, not a confirmed control failure.]


-- =============================================================================
-- Q23. BUSINESS QUESTION: How much of total value comes from the largest
--      transactions, and how are they treated by risk review?
-- WHY IT MATTERS: Q2 showed means far above medians, and Q7 showed review rates
--      rising above NGN 100k. This quantifies the skew by tier and checks whether
--      the highest-value tier is actually where review effort lands.
-- =============================================================================
WITH ranked AS (
    SELECT
        Amount_NGN,
        Risk_Review_Flag,
        NTILE(100) OVER (ORDER BY Amount_NGN DESC) AS pct_bucket
    FROM transactions
    WHERE Transaction_Status = 'Successful'
)
SELECT
    CASE WHEN pct_bucket = 1  THEN '1: top 1% of transactions'
         WHEN pct_bucket <= 5 THEN '2: next 4% (top 5%)'
         WHEN pct_bucket <= 20 THEN '3: next 15% (top 20%)'
         ELSE                       '4: remaining 80%' END AS tier,
    COUNT(*)                                                        AS txn_count,
    ROUND(SUM(Amount_NGN), 0)                                       AS value_ngn,
    ROUND(100.0 * SUM(Amount_NGN) / SUM(SUM(Amount_NGN)) OVER (), 1) AS pct_of_value,
    ROUND(MIN(Amount_NGN), 0)                                       AS min_amount_ngn,
    ROUND(100.0 * SUM(CASE WHEN Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS risk_review_rate_pct
FROM ranked
GROUP BY tier
ORDER BY tier;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [Report what share of value the top 1% and top 5% of transactions carry and
--    the amount at which the top 1% begins (min_amount_ngn). If the top tier
--    holds a large share of value but only a moderate review rate, there is a
--    coverage question: high-value activity may deserve closer review than the
--    current flag provides.]


-- =============================================================================
-- Q24. BUSINESS QUESTION: What is the one-page health summary of FinTrust's
--      transaction business?
-- WHY IT MATTERS: This is the headline row for the dashboard KPI cards
--      (Part D / Part E of the assignment). Every figure here is defined once so
--      the dashboard, report and SQL all agree.
-- =============================================================================
SELECT
    COUNT(*)                                                                                 AS total_transactions,
    COUNT(DISTINCT Customer_ID)                                                              AS active_customers,
    ROUND(100.0 * SUM(CASE WHEN Transaction_Status = 'Successful' THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN Transaction_Status IN ('Failed', 'Reversed') THEN 1 ELSE 0 END) / COUNT(*), 2) AS failed_or_reversed_pct,
    ROUND(SUM(CASE WHEN Transaction_Status = 'Successful' THEN Amount_NGN END), 0)           AS successful_value_ngn,
    ROUND(MEDIAN(CASE WHEN Transaction_Status = 'Successful' THEN Amount_NGN END), 0)        AS median_successful_ngn,
    ROUND(100.0 * SUM(CASE WHEN Risk_Review_Flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2)   AS risk_review_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN International_Transaction = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS international_share_pct
FROM transactions;

-- RESULT:
--   [paste output here]
--
-- BUSINESS INTERPRETATION:
--   [Two or three sentences for management: overall reliability (success and
--    failure rates), scale (successful value and median ticket), and review
--    workload (flag rate and international share). Cross-check the success rate
--    and value against Q1 and Q2; they must match exactly.]
