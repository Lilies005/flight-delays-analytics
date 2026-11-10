-- =====================================================================
-- Objects created:
--   v_causes_delayed_flights  view   the delayed flights we analyse
--   delay_causes              table  one row per delayed flight per cause
--   v_causes_overall          view   dashboard: minutes per cause
--   v_causes_by_airline       view   dashboard: cause mix per airline
--   v_causes_airline_month    view   dashboard filters: airline x month x cause
--   v_causes_delayed_counts   view   dashboard filters: delayed flights per airline x month

-- 0.1 How big is each group?
-- Result: 50044 total, 778 cancelled, 127 diverted,
--         49139 in scope, 9220 delayed (18.8% of in-scope flights)
SELECT
  COUNT(*)                                                     AS total_flights,
  COUNT(*) FILTER (WHERE cancelled = 1)                        AS cancelled,
  COUNT(*) FILTER (WHERE diverted = 1)                         AS diverted,
  COUNT(*) FILTER (WHERE cancelled = 0 AND diverted = 0)       AS in_scope,
  COUNT(*) FILTER (WHERE cancelled = 0 AND diverted = 0
                     AND arrival_delay >= 15)                  AS delayed
FROM flights;

-- 0.2 Does a delayed flight always have at least one cause above 0?
SELECT
  (arrival_delay >= 15) AS is_delayed,
  COUNT(*)              AS flights,
  COUNT(*) FILTER (WHERE air_system_delay    <> 0
                      OR security_delay      <> 0
                      OR airline_delay       <> 0
                      OR late_aircraft_delay <> 0
                      OR weather_delay       <> 0) AS with_a_cause
FROM flights
WHERE cancelled = 0 AND diverted = 0
GROUP BY (arrival_delay >= 15);


-- ---------------------------------------------------------------------
-- 1. Drop our own objects (children first) so the file can be rerun
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS v_causes_airline_month;
DROP VIEW  IF EXISTS v_causes_delayed_counts;
DROP VIEW  IF EXISTS v_causes_by_airline;
DROP VIEW  IF EXISTS v_causes_overall;
DROP TABLE IF EXISTS delay_causes;
DROP VIEW  IF EXISTS v_causes_delayed_flights;


-- ---------------------------------------------------------------------
-- 2. The population: delayed flights, defined once
-- ---------------------------------------------------------------------
-- Columns are listed explicitly (no SELECT *) so the view does not depend
-- on every column of the shared flights table.
CREATE VIEW v_causes_delayed_flights AS
SELECT flight_id, flight_date, month, day_of_week, airline, arrival_delay,
       air_system_delay, security_delay, airline_delay,
       late_aircraft_delay, weather_delay
FROM flights
WHERE cancelled = 0 AND diverted = 0 AND arrival_delay >= 15;


-- ---------------------------------------------------------------------
-- 3. delay_causes: the five cause columns turned into rows
-- ---------------------------------------------------------------------
CREATE TABLE delay_causes (
  delay_cause_id BIGSERIAL PRIMARY KEY,
  flight_id      BIGINT NOT NULL REFERENCES flights(flight_id),
  cause          TEXT   NOT NULL,
  minutes        INT    NOT NULL CHECK (minutes > 0)
);

INSERT INTO delay_causes (flight_id, cause, minutes)
SELECT d.flight_id, c.cause, c.minutes
FROM v_causes_delayed_flights d
CROSS JOIN LATERAL (VALUES
    ('Late aircraft',    d.late_aircraft_delay),
    ('Airline',          d.airline_delay),
    ('Air system (NAS)', d.air_system_delay),
    ('Weather',          d.weather_delay),
    ('Security',         d.security_delay)
) AS c(cause, minutes)
WHERE c.minutes > 0;

CREATE INDEX idx_delay_causes_flight ON delay_causes(flight_id);
CREATE INDEX idx_delay_causes_cause  ON delay_causes(cause);


-- ---------------------------------------------------------------------
-- 4. Validation of the unpivot
-- ---------------------------------------------------------------------

SELECT COUNT(DISTINCT flight_id) AS flights_covered,
       COUNT(*)                  AS cause_rows
FROM delay_causes;

-- 4.2 Totals. The sum of cause minutes must equal the sum of arrival
--     delays of the same flights. Result: 543220 = 543220.
SELECT (SELECT SUM(minutes)       FROM delay_causes)             AS cause_minutes,
       (SELECT SUM(arrival_delay) FROM v_causes_delayed_flights) AS arrival_delay_minutes;

-- 4.3 Flight by flight. exact_match should equal delayed_flights, meaning
--     the five causes fully explain the delay of every flight.
SELECT COUNT(*)                                          AS delayed_flights,
       COUNT(*) FILTER (WHERE s.total = f.arrival_delay) AS exact_match
FROM v_causes_delayed_flights f
JOIN (SELECT flight_id, SUM(minutes) AS total
      FROM delay_causes
      GROUP BY flight_id) s USING (flight_id);


-- ---------------------------------------------------------------------
-- 5. Dashboard view 1: delay minutes per cause
-- ---------------------------------------------------------------------
CREATE VIEW v_causes_overall AS
SELECT cause,
       SUM(minutes)                                               AS total_minutes,
       COUNT(*)                                                   AS flights_affected,
       ROUND(AVG(minutes), 1)                                     AS avg_minutes,
       ROUND(100.0 * SUM(minutes) / SUM(SUM(minutes)) OVER (), 2) AS pct_of_total
FROM delay_causes
GROUP BY cause
ORDER BY total_minutes DESC;


-- ---------------------------------------------------------------------
-- 6. Dashboard view 2: cause mix per airline
-- ---------------------------------------------------------------------
CREATE VIEW v_causes_by_airline AS
SELECT a.airline,
       dc.cause,
       SUM(dc.minutes) AS total_minutes,
       ROUND(100.0 * SUM(dc.minutes)
             / SUM(SUM(dc.minutes)) OVER (PARTITION BY a.airline), 1) AS pct_of_airline
FROM delay_causes dc
JOIN flights  f ON f.flight_id = dc.flight_id
JOIN airlines a ON a.iata_code = f.airline
WHERE f.airline IN (SELECT airline
                    FROM v_causes_delayed_flights
                    GROUP BY airline
                    HAVING COUNT(*) >= 30)
GROUP BY a.airline, dc.cause;


-- ---------------------------------------------------------------------
-- 7. Views behind the dashboard filters (airline and month)
-- ---------------------------------------------------------------------
CREATE VIEW v_causes_airline_month AS
SELECT a.airline,
       f.month,
       dc.cause,
       SUM(dc.minutes) AS total_minutes,
       COUNT(*)        AS flights_affected
FROM delay_causes dc
JOIN flights  f ON f.flight_id = dc.flight_id
JOIN airlines a ON a.iata_code = f.airline
GROUP BY a.airline, f.month, dc.cause;

CREATE VIEW v_causes_delayed_counts AS
SELECT a.airline,
       d.month,
       COUNT(*)             AS delayed_flights,
       SUM(d.arrival_delay) AS delay_minutes
FROM v_causes_delayed_flights d
JOIN airlines a ON a.iata_code = d.airline
GROUP BY a.airline, d.month;

-- 7.1 Check: the totals must match the earlier results.
-- Expected: delay_minutes = 543220 and delayed_flights = 9220.
SELECT SUM(delay_minutes)   AS delay_minutes,
       SUM(delayed_flights) AS delayed_flights
FROM v_causes_delayed_counts;


