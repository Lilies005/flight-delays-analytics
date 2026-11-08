-- sql/delay_causes.sql
DROP VIEW  IF EXISTS v_causes_by_airline;
DROP VIEW  IF EXISTS v_causes_overall;
DROP TABLE IF EXISTS delay_causes;
DROP VIEW  IF EXISTS v_causes_delayed_flights;
DROP VIEW  IF EXISTS delay_cause_and_time_per_flight;  -- your old names
DROP VIEW  IF EXISTS delayed_flights;

-- 1. The eligible population, defined once
CREATE VIEW v_causes_delayed_flights AS
SELECT flight_id, flight_date, month, day_of_week, airline, arrival_delay,
       air_system_delay, security_delay, airline_delay,
       late_aircraft_delay, weather_delay
FROM flights
WHERE cancelled = 0 AND diverted = 0 AND arrival_delay >= 15;

-- 2. The unpivoted table (one row per flight per cause with minutes > 0)
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
select * from delay_causes

CREATE INDEX idx_delay_causes_flight ON delay_causes(flight_id);
CREATE INDEX idx_delay_causes_cause  ON delay_causes(cause);

-- expect: 9220 flights, 15274 rows
SELECT COUNT(DISTINCT flight_id) AS flights_covered, COUNT(*) AS cause_rows
FROM delay_causes;

-- do the causes add up to the delay, flight by flight?
SELECT COUNT(*) AS delayed_flights,
       COUNT(*) FILTER (WHERE s.total = f.arrival_delay) AS exact_match
FROM v_causes_delayed_flights f
JOIN (SELECT flight_id, SUM(minutes) AS total
      FROM delay_causes GROUP BY flight_id) s USING (flight_id);

CREATE VIEW v_causes_overall AS
SELECT cause,
       SUM(minutes)                                               AS total_minutes,
       COUNT(*)                                                   AS flights_affected,
       ROUND(AVG(minutes), 1)                                     AS avg_minutes,
       ROUND(100.0 * SUM(minutes) / SUM(SUM(minutes)) OVER (), 2) AS pct_of_total
FROM delay_causes
GROUP BY cause
ORDER BY total_minutes DESC;
select * from v_causes_overall
CREATE VIEW v_causes_by_airline AS
SELECT a.airline,
       dc.cause,
       SUM(dc.minutes) AS total_minutes,
       ROUND(100.0 * SUM(dc.minutes)
             / SUM(SUM(dc.minutes)) OVER (PARTITION BY a.airline), 1) AS pct_of_airline
FROM delay_causes dc
JOIN flights  f ON f.flight_id = dc.flight_id
JOIN airlines a ON a.iata_code = f.airline
GROUP BY a.airline, dc.cause;
select * from v_causes_by_airline 

-- =====================================================================
-- sql/delay_causes.sql
-- Theme: delay causes 
-- Main question: what are the main causes of flight delays,
--                overall and by airline?
--
-- Objects created:
--   v_causes_delayed_flights  view   the delayed flights we analyse
--   delay_causes              table  one row per delayed flight per cause
--   v_causes_overall          view   dashboard: minutes per cause
--   v_causes_by_airline       view   dashboard: cause mix per airline
-- =====================================================================
-- ---------------------------------------------------------------------
-- 0. Open issue: missing delay causes
-- ---------------------------------------------------------------------
-- The brief says many flights have no recorded cause. In our dataset the
-- missing values were already replaced by 0 when the sample was prepared,
-- so a NULL test finds nothing. The real question is whether a 0 hides a
-- delay that nobody explained. We check it below

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
-- Result: non-delayed flights (39919): 0 with a cause above 0
--         delayed flights (9220): all 9220 have at least one cause above 0

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
DROP VIEW  IF EXISTS v_causes_by_airline;
DROP VIEW  IF EXISTS v_causes_overall;
DROP TABLE IF EXISTS delay_causes;
DROP VIEW  IF EXISTS v_causes_delayed_flights;
 
 
-- ---------------------------------------------------------------------
-- 2. The population: delayed flights, defined once
-- ---------------------------------------------------------------------
CREATE VIEW v_causes_delayed_flights AS
SELECT flight_id, flight_date, month, day_of_week, airline, arrival_delay,
       air_system_delay, security_delay, airline_delay,
       late_aircraft_delay, weather_delay
FROM flights
WHERE cancelled = 0 AND diverted = 0 AND arrival_delay >= 15;
-- ---------------------------------------------------------------------
-- 3. delay_causes: the five cause columns turned into rows
-- ---------------------------------------------------------------------
-- arrival_delay is the total that the five causes add up to, and 
-- departure_delay is how late the plane left, not why. Including 
-- them would count minutes twice

CREATE TABLE delay_causes (
  delay_cause_id BIGSERIAL PRIMARY KEY,
  flight_id      BIGINT NOT NULL REFERENCES flights(flight_id),
  cause          TEXT   NOT NULL,
  minutes        INT    NOT NULL CHECK (minutes > 0)
);
--Unpivotng step : 

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
-- 4.1 Coverage. Expected: 9220 flights, 15274 cause rows 

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
-- total_minutes    : how much delay the cause produced
-- flights_affected : how many delayed flights it touched
-- avg_minutes      : how severe it is when it happens
-- pct_of_total     : each cause is divided by the total of all causes

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
-- We compare shares and not raw minutes, because big airlines have more
-- delay minutes simply because they fly more. PARTITION BY airline makes
-- the window total restart for each airline, so every airline adds up to
-- 100%.
-- Team rule: only airlines with at least 30 delayed flights are kept, so
-- the shares are never computed on a tiny sample. To see how many delayed
-- flights each airline has:
--   SELECT airline, COUNT(*) FROM v_causes_delayed_flights
--   GROUP BY airline ORDER BY 2;
-- A cause with 0 minutes for an airline has no row, so the dashboard must
-- fill the gaps with 0 when it pivots the data.

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
 
 -- ----------------------------------------------------------------------- --
 --                               THANK YOU !                               --
 -- ----------------------------------------------------------------------- --
