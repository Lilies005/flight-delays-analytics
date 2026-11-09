-- =====================================================================
-- Person 5 - Cancellations      (file: sql/cancellations.sql)
-- Question: When and why are flights cancelled?
-- Rules:
--   * cancellation rate = cancelled flights / ALL scheduled flights
--     (cancelled flights must stay in the denominator)
--   * minimum 30 flights per group (HAVING COUNT(*) >= 30)
-- Open Issue: cancelled flights have NULL in the delay columns.
--   Any average delay must filter cancelled = 0 (see v_cancel_avg_delay_check).
-- CASE is used to replace cancellation codes with readable names.
-- =====================================================================

-- 1) Cancellation rate by airline, compared with the overall rate, ranked
CREATE OR REPLACE VIEW v_cancel_by_airline AS
WITH overall AS (
  SELECT 100.0 * SUM(cancelled) / COUNT(*) AS overall_rate FROM flights
),
per_airline AS (
  SELECT f.airline AS airline_code,
         a.airline AS airline_name,
         COUNT(*) AS nb_flights,
         SUM(f.cancelled) AS nb_cancelled,
         ROUND(100.0 * SUM(f.cancelled) / COUNT(*), 2) AS cancel_rate_pct
  FROM flights f
  LEFT JOIN airlines a ON a.iata_code = f.airline
  GROUP BY f.airline, a.airline
  HAVING COUNT(*) >= 30
)
SELECT p.*,
       ROUND(p.cancel_rate_pct - o.overall_rate, 2) AS vs_overall_pts,
       RANK() OVER (ORDER BY p.cancel_rate_pct DESC) AS worst_rank
FROM per_airline p CROSS JOIN overall o
ORDER BY p.cancel_rate_pct DESC;

-- 2) Cancellation rate by month, with LAG() for the month-to-month change
CREATE OR REPLACE VIEW v_cancel_by_month AS
WITH monthly AS (
  SELECT year, month,
         COUNT(*) AS nb_flights,
         SUM(cancelled) AS nb_cancelled,
         ROUND(100.0 * SUM(cancelled) / COUNT(*), 2) AS cancel_rate_pct
  FROM flights
  GROUP BY year, month
)
SELECT year, month, nb_flights, nb_cancelled, cancel_rate_pct,
       LAG(cancel_rate_pct) OVER (ORDER BY year, month) AS prev_month_rate_pct,
       ROUND(cancel_rate_pct - LAG(cancel_rate_pct) OVER (ORDER BY year, month), 2) AS change_pts
FROM monthly
ORDER BY year, month;

-- 3) Cancellation reasons (CASE gives readable names; NULL codes -> Unknown)
CREATE OR REPLACE VIEW v_cancel_reasons AS
SELECT CASE COALESCE(cancellation_reason, 'UNKNOWN')
         WHEN 'A' THEN 'Airline / Carrier'
         WHEN 'B' THEN 'Weather'
         WHEN 'C' THEN 'National Air System'
         WHEN 'D' THEN 'Security'
         ELSE 'Unknown reason'
       END AS reason,
       COUNT(*) AS nb_cancelled,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM flights
WHERE cancelled = 1
GROUP BY 1
ORDER BY nb_cancelled DESC;

-- 4) Reason x month (seasonal patterns)
CREATE OR REPLACE VIEW v_cancel_reason_month AS
SELECT month,
       CASE COALESCE(cancellation_reason, 'UNKNOWN')
         WHEN 'A' THEN 'Airline / Carrier'
         WHEN 'B' THEN 'Weather'
         WHEN 'C' THEN 'National Air System'
         WHEN 'D' THEN 'Security'
         ELSE 'Unknown reason'
       END AS reason,
       COUNT(*) AS nb_cancelled
FROM flights
WHERE cancelled = 1
GROUP BY month, 2
ORDER BY month, nb_cancelled DESC;

-- 5) Open Issue demo: correct average delay per airline (cancelled/diverted excluded)
CREATE OR REPLACE VIEW v_cancel_avg_delay_check AS
SELECT airline,
       COUNT(*) AS nb_flights,
       SUM(cancelled) AS nb_cancelled,
       ROUND(AVG(arrival_delay) FILTER (WHERE cancelled = 0 AND diverted = 0), 2) AS avg_arrival_delay_min
FROM flights
GROUP BY airline;