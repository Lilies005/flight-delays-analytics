-- =====================================================================
-- sql/cancellations.sql  |  Person 5: when and why are flights cancelled?
-- Rules: rate = cancelled / ALL scheduled flights; min 30 flights per group.
-- Open issue: cancelled flights have no delay values, so every average
-- delay excludes them (see v_cancel_delay_check).
-- Safe to rerun: drops only its own objects. Never modifies shared tables.
-- =====================================================================

DROP VIEW IF EXISTS v_cancel_quality;
DROP VIEW IF EXISTS v_cancel_delay_check;
DROP VIEW IF EXISTS v_cancel_avg_delay_check;   -- old name
DROP VIEW IF EXISTS v_cancel_reason_month;
DROP VIEW IF EXISTS v_cancel_reasons;
DROP VIEW IF EXISTS v_cancel_by_month;
DROP VIEW IF EXISTS v_cancel_by_airline;
DROP VIEW IF EXISTS v_cancel_overall;
DROP VIEW IF EXISTS v_cancel_airline_month_reason;
DROP VIEW IF EXISTS v_cancel_airline_month;


-- Wilson 95% interval (in %), identical to the helper in time.sql
CREATE OR REPLACE FUNCTION rate_ci_low(x numeric, n numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT ROUND(100 * ((x/n + 1.96^2/(2*n))
         - 1.96 * SQRT((x/n) * (1 - x/n) / n + 1.96^2 / (4 * n^2)))
         / (1 + 1.96^2 / n), 2)
$$;

CREATE OR REPLACE FUNCTION rate_ci_high(x numeric, n numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT ROUND(100 * ((x/n + 1.96^2/(2*n))
         + 1.96 * SQRT((x/n) * (1 - x/n) / n + 1.96^2 / (4 * n^2)))
         / (1 + 1.96^2 / n), 2)
$$;


-- 1) Finest grain: flights per airline x month (feeds every view and the dashboard)
CREATE VIEW v_cancel_airline_month AS
SELECT f.airline                          AS airline_code,
       COALESCE(a.airline, f.airline)     AS airline_name,
       f.year, f.month,
       COUNT(*)                           AS nb_flights,
       COUNT(*) FILTER (WHERE f.cancelled = 1) AS nb_cancelled
FROM flights f
LEFT JOIN airlines a ON a.iata_code = f.airline
GROUP BY f.airline, a.airline, f.year, f.month;


-- 2) Finest grain: cancelled flights per airline x month x reason (CASE = readable names)
CREATE VIEW v_cancel_airline_month_reason AS
WITH c AS (
  SELECT airline, year, month,
         COALESCE(NULLIF(TRIM(cancellation_reason), ''), 'UNK') AS code
  FROM flights
  WHERE cancelled = 1
)
SELECT c.airline                      AS airline_code,
       COALESCE(a.airline, c.airline) AS airline_name,
       c.year, c.month,
       c.code                         AS reason_code,
       CASE c.code
         WHEN 'A' THEN 'Airline'
         WHEN 'B' THEN 'Weather'
         WHEN 'C' THEN 'Air system (NAS)'
         WHEN 'D' THEN 'Security'
         ELSE 'Unknown'
       END                            AS reason,
       COUNT(*)                       AS nb_cancelled
FROM c
LEFT JOIN airlines a ON a.iata_code = c.airline
GROUP BY c.airline, a.airline, c.year, c.month, c.code;


-- 3) Overall rate (one row)
CREATE VIEW v_cancel_overall AS
SELECT SUM(nb_flights)::int    AS nb_flights,
       SUM(nb_cancelled)::int  AS nb_cancelled,
       ROUND(100.0 * SUM(nb_cancelled) / SUM(nb_flights), 2) AS cancel_rate_pct,
       rate_ci_low(SUM(nb_cancelled), SUM(nb_flights))       AS ci_low_pct,
       rate_ci_high(SUM(nb_cancelled), SUM(nb_flights))      AS ci_high_pct
FROM v_cancel_airline_month;


-- 4) Rate by airline: interval, gap to overall, significance, airline-caused share
CREATE VIEW v_cancel_by_airline AS
WITH per AS (
  SELECT airline_code, airline_name,
         SUM(nb_flights)::int   AS nb_flights,
         SUM(nb_cancelled)::int AS nb_cancelled
  FROM v_cancel_airline_month
  GROUP BY airline_code, airline_name
  HAVING SUM(nb_flights) >= 30
),
carrier AS (
  SELECT airline_code, SUM(nb_cancelled)::int AS nb_airline_caused
  FROM v_cancel_airline_month_reason
  WHERE reason_code = 'A'
  GROUP BY airline_code
),
rated AS (
  SELECT p.*,
         ROUND(100.0 * p.nb_cancelled / p.nb_flights, 2) AS cancel_rate_pct,
         rate_ci_low(p.nb_cancelled, p.nb_flights)       AS ci_low_pct,
         rate_ci_high(p.nb_cancelled, p.nb_flights)      AS ci_high_pct,
         COALESCE(c.nb_airline_caused, 0)                AS nb_airline_caused
  FROM per p
  LEFT JOIN carrier c USING (airline_code)
)
SELECT r.airline_code, r.airline_name, r.nb_flights, r.nb_cancelled,
       r.cancel_rate_pct, r.ci_low_pct, r.ci_high_pct,
       ROUND(r.cancel_rate_pct - o.cancel_rate_pct, 2) AS vs_overall_pts,
       CASE WHEN r.ci_low_pct  > o.cancel_rate_pct THEN 'Above overall'
            WHEN r.ci_high_pct < o.cancel_rate_pct THEN 'Below overall'
            ELSE 'In line' END                          AS signal,
       r.nb_airline_caused,
       ROUND(100.0 * r.nb_airline_caused / NULLIF(r.nb_cancelled, 0), 1) AS airline_caused_pct,
       RANK() OVER (ORDER BY r.cancel_rate_pct DESC)    AS worst_rank
FROM rated r CROSS JOIN v_cancel_overall o;


-- 5) Rate by month, with month-to-month change (LAG)
CREATE VIEW v_cancel_by_month AS
WITH g AS (
  SELECT year, month,
         SUM(nb_flights)::int   AS nb_flights,
         SUM(nb_cancelled)::int AS nb_cancelled
  FROM v_cancel_airline_month
  GROUP BY year, month
  HAVING SUM(nb_flights) >= 30
),
r AS (
  SELECT g.*,
         year::text || '-' || LPAD(month::text, 2, '0')   AS period,
         TO_CHAR(TO_DATE(month::text, 'MM'), 'Mon')       AS month_name,
         ROUND(100.0 * nb_cancelled / nb_flights, 2)      AS cancel_rate_pct,
         rate_ci_low(nb_cancelled, nb_flights)            AS ci_low_pct,
         rate_ci_high(nb_cancelled, nb_flights)           AS ci_high_pct
  FROM g
)
SELECT r.year, r.month, r.period, r.month_name,
       r.nb_flights, r.nb_cancelled, r.cancel_rate_pct, r.ci_low_pct, r.ci_high_pct,
       LAG(r.cancel_rate_pct) OVER (ORDER BY r.year, r.month) AS prev_month_rate_pct,
       ROUND(r.cancel_rate_pct - LAG(r.cancel_rate_pct) OVER (ORDER BY r.year, r.month), 2) AS change_pts,
       ROUND(r.cancel_rate_pct - o.cancel_rate_pct, 2)        AS vs_overall_pts,
       RANK() OVER (ORDER BY r.cancel_rate_pct DESC)          AS worst_rank
FROM r CROSS JOIN v_cancel_overall o;


-- 6) Reasons: count, share of cancellations, and rate per 1,000 scheduled flights
CREATE VIEW v_cancel_reasons AS
SELECT reason_code, reason,
       SUM(nb_cancelled)::int AS nb_cancelled,
       ROUND(100.0 * SUM(nb_cancelled) / SUM(SUM(nb_cancelled)) OVER (), 2) AS share_pct,
       ROUND(1000.0 * SUM(nb_cancelled) / (SELECT nb_flights FROM v_cancel_overall), 2) AS per_1000_flights
FROM v_cancel_airline_month_reason
GROUP BY reason_code, reason;


-- 7) Reason x month, zero-filled, as counts, per 1,000 flights and share of the month
CREATE VIEW v_cancel_reason_month AS
SELECT m.year, m.month, m.period, m.month_name,
       r.reason_code, r.reason,
       COALESCE(x.n, 0)::int AS nb_cancelled,
       m.nb_flights,
       ROUND(1000.0 * COALESCE(x.n, 0) / m.nb_flights, 2)                  AS per_1000_flights,
       ROUND(100.0 * COALESCE(x.n, 0) / NULLIF(m.nb_cancelled, 0), 1)      AS share_of_month_pct
FROM v_cancel_by_month m
CROSS JOIN (SELECT DISTINCT reason_code, reason FROM v_cancel_airline_month_reason) r
LEFT JOIN (
  SELECT year, month, reason_code, SUM(nb_cancelled) AS n
  FROM v_cancel_airline_month_reason
  GROUP BY year, month, reason_code
) x ON x.year = m.year AND x.month = m.month AND x.reason_code = r.reason_code;


-- 8) Open issue: wrong vs correct average arrival delay per airline
--    wrong   = NULL turned into 0 (cancelled and diverted flights count as on time)
--    correct = completed flights only
CREATE VIEW v_cancel_delay_check AS
SELECT COALESCE(a.airline, f.airline) AS airline_name,
       COUNT(*)                                          AS nb_flights,
       COUNT(*) FILTER (WHERE f.cancelled = 1)           AS nb_cancelled,
       ROUND(AVG(f.arrival_delay) FILTER (WHERE f.cancelled = 0 AND f.diverted = 0), 2) AS avg_delay_correct_min,
       ROUND(AVG(COALESCE(f.arrival_delay, 0)), 2)       AS avg_delay_wrong_min,
       ROUND(AVG(COALESCE(f.arrival_delay, 0))
           - AVG(f.arrival_delay) FILTER (WHERE f.cancelled = 0 AND f.diverted = 0), 2) AS bias_min
FROM flights f
LEFT JOIN airlines a ON a.iata_code = f.airline
GROUP BY COALESCE(a.airline, f.airline)
HAVING COUNT(*) >= 30;


-- 9) Data quality (one row). Expected: *_must_be_0 = 0 and cancelled_with_zero_delay = 0
CREATE VIEW v_cancel_quality AS
SELECT COUNT(*)                                                     AS total_flights,
       COUNT(*) FILTER (WHERE cancelled = 1)                        AS cancelled_flights,
       COUNT(*) FILTER (WHERE cancelled = 1 AND arrival_delay IS NULL)   AS cancelled_null_arrival_delay,
       COUNT(*) FILTER (WHERE cancelled = 1 AND arrival_delay = 0)       AS cancelled_with_zero_delay,
       COUNT(*) FILTER (WHERE cancelled = 1 AND departure_delay IS NULL) AS cancelled_null_departure_delay,
       COUNT(*) FILTER (WHERE cancelled = 1
                          AND COALESCE(NULLIF(TRIM(cancellation_reason), ''), 'UNK') NOT IN ('A','B','C','D'))
                                                                    AS cancelled_unknown_reason,
       COUNT(*) FILTER (WHERE cancelled = 0
                          AND NULLIF(TRIM(cancellation_reason), '') IS NOT NULL)
                                                                    AS reason_on_completed_must_be_0,
       COUNT(*) FILTER (WHERE cancelled = 1 AND diverted = 1)       AS cancelled_and_diverted_must_be_0,
       COUNT(*) FILTER (WHERE airline NOT IN (SELECT iata_code FROM airlines))
                                                                    AS unmatched_airline_must_be_0,
       COUNT(DISTINCT year * 100 + month)                           AS months_covered
FROM flights;


-- Read (order is applied here, not in the views)
-- SELECT * FROM v_cancel_by_airline  ORDER BY worst_rank;
-- SELECT * FROM v_cancel_by_month    ORDER BY year, month;
-- SELECT * FROM v_cancel_reasons     ORDER BY nb_cancelled DESC;
-- SELECT * FROM v_cancel_reason_month ORDER BY year, month, reason_code;
-- SELECT * FROM v_cancel_delay_check ORDER BY bias_min DESC;
-- SELECT * FROM v_cancel_quality;