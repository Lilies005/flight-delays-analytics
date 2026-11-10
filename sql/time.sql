

DROP VIEW IF EXISTS v_time_quality;
DROP VIEW IF EXISTS v_time_by_period;
DROP VIEW IF EXISTS v_time_monthly_trend;
DROP VIEW IF EXISTS v_time_hour_weekday;
DROP VIEW IF EXISTS v_time_by_weekday;
DROP VIEW IF EXISTS v_time_by_hour;
DROP VIEW IF EXISTS v_time_overall;
DROP VIEW IF EXISTS v_time_cube;
DROP VIEW IF EXISTS v_time_eligible;


-- Wilson 95% interval (in %), identical to the helper in cancellations.sql
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


-- 1) The population, defined once (valid hour required)
CREATE VIEW v_time_eligible AS
SELECT flight_id, flight_date, year, month, day_of_week,
       scheduled_hour, airline, arrival_delay,
       (arrival_delay >= 15) AS is_delayed,
       CASE WHEN scheduled_hour BETWEEN 5  AND 11 THEN 1
            WHEN scheduled_hour BETWEEN 12 AND 17 THEN 2
            WHEN scheduled_hour BETWEEN 18 AND 22 THEN 3
            ELSE 4 END AS period_order
FROM flights
WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL
  AND scheduled_hour BETWEEN 0 AND 23;


-- 2) Finest grain: airline x month x weekday x hour (feeds every view and the dashboard)
CREATE VIEW v_time_cube AS
SELECT e.airline                       AS airline_code,
       COALESCE(a.airline, e.airline)  AS airline_name,
       e.year, e.month, e.day_of_week,
       CASE e.day_of_week
         WHEN 1 THEN 'Monday'   WHEN 2 THEN 'Tuesday'  WHEN 3 THEN 'Wednesday'
         WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'   WHEN 6 THEN 'Saturday'
         WHEN 7 THEN 'Sunday'
       END                             AS day_name,
       e.scheduled_hour                AS hour_of_day,
       e.period_order,
       CASE e.period_order
         WHEN 1 THEN 'Morning (05-11h)'
         WHEN 2 THEN 'Afternoon (12-17h)'
         WHEN 3 THEN 'Evening (18-22h)'
         ELSE 'Night (23-04h)'
       END                             AS period,
       COUNT(*)                        AS nb_flights,
       COUNT(*) FILTER (WHERE e.is_delayed) AS nb_delayed,
       COALESCE(SUM(e.arrival_delay) FILTER (WHERE e.is_delayed), 0) AS late_minutes
FROM v_time_eligible e
LEFT JOIN airlines a ON a.iata_code = e.airline
GROUP BY e.airline, a.airline, e.year, e.month, e.day_of_week,
         e.scheduled_hour, e.period_order;


-- 3) Overall rate (one row)
CREATE VIEW v_time_overall AS
SELECT SUM(nb_flights)::int  AS nb_flights,
       SUM(nb_delayed)::int  AS nb_delayed,
       ROUND(100.0 * SUM(nb_delayed) / SUM(nb_flights), 2) AS delay_rate_pct,
       rate_ci_low(SUM(nb_delayed), SUM(nb_flights))       AS ci_low_pct,
       rate_ci_high(SUM(nb_delayed), SUM(nb_flights))      AS ci_high_pct
FROM v_time_cube;


-- 4) Delay rate by hour (interval, gap to overall, significance, rank)
CREATE VIEW v_time_by_hour AS
WITH g AS (
  SELECT hour_of_day,
         SUM(nb_flights)::int AS nb_flights, SUM(nb_delayed)::int AS nb_delayed,
         SUM(late_minutes)    AS late_minutes
  FROM v_time_cube
  GROUP BY hour_of_day
  HAVING SUM(nb_flights) >= 30
),
r AS (
  SELECT g.*,
         ROUND(100.0 * nb_delayed / nb_flights, 2)           AS delay_rate_pct,
         rate_ci_low(nb_delayed, nb_flights)                 AS ci_low_pct,
         rate_ci_high(nb_delayed, nb_flights)                AS ci_high_pct,
         ROUND(late_minutes::numeric / NULLIF(nb_delayed, 0), 1) AS avg_delay_when_late_min
  FROM g
)
SELECT r.hour_of_day, r.nb_flights, r.nb_delayed, r.delay_rate_pct,
       r.ci_low_pct, r.ci_high_pct, r.avg_delay_when_late_min,
       ROUND(r.delay_rate_pct - o.delay_rate_pct, 2) AS vs_overall_pts,
       CASE WHEN r.ci_low_pct  > o.delay_rate_pct THEN 'Above overall'
            WHEN r.ci_high_pct < o.delay_rate_pct THEN 'Below overall'
            ELSE 'In line' END                        AS signal,
       RANK() OVER (ORDER BY r.delay_rate_pct DESC)   AS worst_rank
FROM r CROSS JOIN v_time_overall o;


-- 5) Delay rate by weekday (1 = Monday ... 7 = Sunday)
CREATE VIEW v_time_by_weekday AS
WITH g AS (
  SELECT day_of_week, day_name,
         SUM(nb_flights)::int AS nb_flights, SUM(nb_delayed)::int AS nb_delayed,
         SUM(late_minutes)    AS late_minutes
  FROM v_time_cube
  GROUP BY day_of_week, day_name
  HAVING SUM(nb_flights) >= 30
),
r AS (
  SELECT g.*,
         ROUND(100.0 * nb_delayed / nb_flights, 2)           AS delay_rate_pct,
         rate_ci_low(nb_delayed, nb_flights)                 AS ci_low_pct,
         rate_ci_high(nb_delayed, nb_flights)                AS ci_high_pct,
         ROUND(late_minutes::numeric / NULLIF(nb_delayed, 0), 1) AS avg_delay_when_late_min
  FROM g
)
SELECT r.day_of_week, r.day_name, r.nb_flights, r.nb_delayed, r.delay_rate_pct,
       r.ci_low_pct, r.ci_high_pct, r.avg_delay_when_late_min,
       ROUND(r.delay_rate_pct - o.delay_rate_pct, 2) AS vs_overall_pts,
       CASE WHEN r.ci_low_pct  > o.delay_rate_pct THEN 'Above overall'
            WHEN r.ci_high_pct < o.delay_rate_pct THEN 'Below overall'
            ELSE 'In line' END                        AS signal,
       RANK() OVER (ORDER BY r.delay_rate_pct DESC)   AS worst_rank
FROM r CROSS JOIN v_time_overall o;


-- 6) Heatmap: weekday x hour (stricter minimum: 100 flights per cell)
CREATE VIEW v_time_hour_weekday AS
SELECT day_of_week, day_name, hour_of_day,
       SUM(nb_flights)::int AS nb_flights,
       ROUND(100.0 * SUM(nb_delayed) / SUM(nb_flights), 2) AS delay_rate_pct
FROM v_time_cube
GROUP BY day_of_week, day_name, hour_of_day
HAVING SUM(nb_flights) >= 30;


-- 7) Monthly trend with month-to-month change (LAG)
CREATE VIEW v_time_monthly_trend AS
WITH g AS (
  SELECT year, month,
         SUM(nb_flights)::int AS nb_flights, SUM(nb_delayed)::int AS nb_delayed
  FROM v_time_cube
  GROUP BY year, month
  HAVING SUM(nb_flights) >= 30
),
r AS (
  SELECT g.*,
         year::text || '-' || LPAD(month::text, 2, '0')   AS period,
         TO_CHAR(TO_DATE(month::text, 'MM'), 'Mon')       AS month_name,
         ROUND(100.0 * nb_delayed / nb_flights, 2)        AS delay_rate_pct,
         rate_ci_low(nb_delayed, nb_flights)              AS ci_low_pct,
         rate_ci_high(nb_delayed, nb_flights)             AS ci_high_pct
  FROM g
)
SELECT r.year, r.month, r.period, r.month_name, r.nb_flights, r.nb_delayed,
       r.delay_rate_pct, r.ci_low_pct, r.ci_high_pct,
       LAG(r.delay_rate_pct) OVER (ORDER BY r.year, r.month) AS prev_month_rate_pct,
       ROUND(r.delay_rate_pct - LAG(r.delay_rate_pct) OVER (ORDER BY r.year, r.month), 2) AS change_pts
FROM r;


-- 8) Time-of-day buckets
CREATE VIEW v_time_by_period AS
WITH g AS (
  SELECT period_order, period,
         SUM(nb_flights)::int AS nb_flights, SUM(nb_delayed)::int AS nb_delayed
  FROM v_time_cube
  GROUP BY period_order, period
  HAVING SUM(nb_flights) >= 30
)
SELECT g.period_order, g.period, g.nb_flights, g.nb_delayed,
       ROUND(100.0 * g.nb_delayed / g.nb_flights, 2) AS delay_rate_pct,
       rate_ci_low(g.nb_delayed, g.nb_flights)       AS ci_low_pct,
       rate_ci_high(g.nb_delayed, g.nb_flights)      AS ci_high_pct,
       ROUND(ROUND(100.0 * g.nb_delayed / g.nb_flights, 2) - o.delay_rate_pct, 2) AS vs_overall_pts
FROM g CROSS JOIN v_time_overall o;


-- 9) Data quality (one row). Expected: every *_must_be_0 column = 0
--    scheduled_hour_min = 0 and scheduled_hour_max = 23
CREATE VIEW v_time_quality AS
SELECT COUNT(*)                                                         AS total_flights,
       COUNT(*) FILTER (WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NOT NULL) AS eligible_before_hour_check,
       (SELECT COUNT(*) FROM v_time_eligible)                           AS eligible_flights,
       COUNT(*) FILTER (WHERE cancelled = 0 AND diverted = 0
                          AND arrival_delay IS NULL)                    AS completed_missing_delay_must_be_0,
       COUNT(*) FILTER (WHERE scheduled_hour IS NULL
                           OR scheduled_hour NOT BETWEEN 0 AND 23)      AS bad_hour_must_be_0,
       MIN(scheduled_hour)                                              AS scheduled_hour_min,
       MAX(scheduled_hour)                                              AS scheduled_hour_max,
       COUNT(*) FILTER (WHERE day_of_week::int <> EXTRACT(ISODOW FROM flight_date)::int)
                                                                        AS weekday_mismatch_must_be_0,
       COUNT(DISTINCT year * 100 + month)                               AS months_covered
FROM flights;


-- SELECT * FROM v_time_by_hour       ORDER BY hour_of_day;
-- SELECT * FROM v_time_by_weekday    ORDER BY day_of_week;
-- SELECT * FROM v_time_monthly_trend ORDER BY year, month;
-- SELECT * FROM v_time_by_period     ORDER BY period_order;
-- SELECT * FROM v_time_quality;
-- Optional, if scheduled_departure is kept in flights (should be > 0 and all land in hour 0):
-- SELECT COUNT(*), COUNT(*) FILTER (WHERE scheduled_hour = 0) FROM flights WHERE scheduled_departure = 2400;