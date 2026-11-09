-- =====================================================================
-- Person 3 - Time Analysis      (file: sql/time.sql)
-- Question: When do flight delays happen most often?
-- Rules (shared by the team):
--   * delayed = arrival_delay >= 15
--   * eligible flights: cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
--   * minimum 30 eligible flights per group (HAVING COUNT(*) >= 30)
-- Open Issue (HHMM format): scheduled_hour was computed at load time as
--   (scheduled_departure / 100) % 24   ->  1530 = 15,  2400 = 0
-- Note: hour = scheduled DEPARTURE hour; the delay is measured at ARRIVAL.
-- =====================================================================

-- 1) Delay rate by hour, compared with the overall rate, ranked
CREATE OR REPLACE VIEW v_time_by_hour AS
WITH overall AS (
  SELECT 100.0 * COUNT(*) FILTER (WHERE arrival_delay >= 15) / COUNT(*) AS overall_rate
  FROM flights
  WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
),
hourly AS (
  SELECT scheduled_hour AS hour_of_day,
         COUNT(*) AS nb_flights,
         COUNT(*) FILTER (WHERE arrival_delay >= 15) AS nb_delayed,
         ROUND(100.0 * COUNT(*) FILTER (WHERE arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct,
         ROUND(AVG(arrival_delay) FILTER (WHERE arrival_delay >= 15), 1) AS avg_delay_when_late_min
  FROM flights
  WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
  GROUP BY scheduled_hour
  HAVING COUNT(*) >= 30
)
SELECT h.*,
       ROUND(h.delay_rate_pct - o.overall_rate, 2) AS vs_overall_pts,
       RANK() OVER (ORDER BY h.delay_rate_pct DESC) AS worst_rank
FROM hourly h CROSS JOIN overall o
ORDER BY h.hour_of_day;

-- 2) Delay rate by day of week (1 = Monday ... 7 = Sunday), compared and ranked
CREATE OR REPLACE VIEW v_time_by_weekday AS
WITH overall AS (
  SELECT 100.0 * COUNT(*) FILTER (WHERE arrival_delay >= 15) / COUNT(*) AS overall_rate
  FROM flights
  WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
),
daily AS (
  SELECT day_of_week,
         CASE day_of_week
              WHEN 1 THEN 'Monday'    WHEN 2 THEN 'Tuesday'
              WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday'
              WHEN 5 THEN 'Friday'    WHEN 6 THEN 'Saturday'
              WHEN 7 THEN 'Sunday'
         END AS day_name,
         COUNT(*) AS nb_flights,
         COUNT(*) FILTER (WHERE arrival_delay >= 15) AS nb_delayed,
         ROUND(100.0 * COUNT(*) FILTER (WHERE arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct,
         ROUND(AVG(arrival_delay) FILTER (WHERE arrival_delay >= 15), 1) AS avg_delay_when_late_min
  FROM flights
  WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
  GROUP BY day_of_week
  HAVING COUNT(*) >= 30
)
SELECT d.*,
       ROUND(d.delay_rate_pct - o.overall_rate, 2) AS vs_overall_pts,
       RANK() OVER (ORDER BY d.delay_rate_pct DESC) AS worst_rank
FROM daily d CROSS JOIN overall o
ORDER BY d.day_of_week;

-- 3) Hour x weekday (for a heatmap)
CREATE OR REPLACE VIEW v_time_hour_weekday AS
SELECT day_of_week,
       scheduled_hour AS hour_of_day,
       COUNT(*) AS nb_flights,
       ROUND(100.0 * COUNT(*) FILTER (WHERE arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct
FROM flights
WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
GROUP BY day_of_week, scheduled_hour
HAVING COUNT(*) >= 30;

-- 4) Monthly trend with LAG()
CREATE OR REPLACE VIEW v_time_monthly_trend AS
WITH monthly AS (
  SELECT year, month,
         COUNT(*) AS nb_flights,
         ROUND(100.0 * COUNT(*) FILTER (WHERE arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct
  FROM flights
  WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
  GROUP BY year, month
)
SELECT year, month, nb_flights, delay_rate_pct,
       LAG(delay_rate_pct) OVER (ORDER BY year, month) AS prev_month_rate_pct,
       ROUND(delay_rate_pct - LAG(delay_rate_pct) OVER (ORDER BY year, month), 2) AS change_pts
FROM monthly
ORDER BY year, month;

-- 5) Time-of-day buckets (easy to present to executives)
CREATE OR REPLACE VIEW v_time_by_period AS
SELECT CASE WHEN scheduled_hour BETWEEN 5  AND 11 THEN '1 - Morning (05-11h)'
            WHEN scheduled_hour BETWEEN 12 AND 17 THEN '2 - Afternoon (12-17h)'
            WHEN scheduled_hour BETWEEN 18 AND 22 THEN '3 - Evening (18-22h)'
            ELSE '4 - Night (23-04h)' END AS period,
       COUNT(*) AS nb_flights,
       ROUND(100.0 * COUNT(*) FILTER (WHERE arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct
FROM flights
WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Check (run manually): day_of_week numbering vs real day names
-- SELECT day_of_week, TO_CHAR(flight_date, 'Day') AS real_day, COUNT(*)
-- FROM flights GROUP BY 1, 2 ORDER BY 1;