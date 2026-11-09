-- =====================================================================
-- sql/delay_causes.sql
-- Theme: delay causes (Person 4)
-- Main question: what are the main causes of flight delays,
--                overall and by airline?
--
-- Run this file after the base script (tables created, CSVs loaded,
-- INSERT INTO flights done). It only creates and drops its own objects
-- and never modifies flights or any other shared table, so it can be
-- rerun safely.
--
-- Objects created:
--   v_causes_delayed_flights  view   the delayed flights we analyse
--   delay_causes              table  one row per delayed flight per cause
--   v_causes_overall          view   dashboard: minutes per cause
--   v_causes_by_airline       view   dashboard: cause mix per airline
--   v_causes_airline_month    view   dashboard filters: airline x month x cause
--   v_causes_delayed_counts   view   dashboard filters: delayed flights per airline x month
--
-- Team rules applied:
--   delayed  = arrival_delay >= 15
--   in scope = cancelled = 0 AND diverted = 0
--   (arrival_delay >= 15 is never true for a NULL, so flights with a
--    NULL arrival_delay are excluded automatically)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Open issue: missing delay causes
-- ---------------------------------------------------------------------
-- The brief says many flights have no recorded cause. In our dataset the
-- missing values were already replaced by 0 when the sample was prepared,
-- so a NULL test finds nothing. The real question is whether a 0 hides a
-- delay that nobody explained. We check it below (diagnostic only, no
-- objects are created in this section).

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
-- Decision: a 0 on a non-delayed flight means "nothing to attribute", and
-- no delayed flight is left unexplained, so no "unattributed" category is
-- needed. The cause analysis only uses delayed flights, and zero-minute
-- causes are not stored. This holds for this 50,000-flight sample.
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
-- One row per delayed flight per cause with minutes > 0.
-- arrival_delay and departure_delay are NOT causes: arrival_delay is the
-- total that the five causes add up to, and departure_delay is how late
-- the plane left, not why. Including them would count minutes twice.
CREATE TABLE delay_causes (
  delay_cause_id BIGSERIAL PRIMARY KEY,
  flight_id      BIGINT NOT NULL REFERENCES flights(flight_id),
  cause          TEXT   NOT NULL,
  minutes        INT    NOT NULL CHECK (minutes > 0)
);

-- CROSS JOIN LATERAL lets the VALUES list read the columns of the flight
-- on its left, so each flight is expanded into five candidate rows in a
-- single pass over the data. The WHERE keeps only causes above 0.
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
--     (4849 + 4914 + 4887 + 594 + 30 flights per cause).
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
-- flights_affected : how many delayed flights it touched (a flight can
--                    have several causes, so the column adds up to more
--                    than 9220)
-- avg_minutes      : how severe it is when it happens
-- pct_of_total     : SUM(SUM(minutes)) OVER () is the grand total, so each
--                    cause is divided by the total of all causes
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


-- ---------------------------------------------------------------------
-- 7. Views behind the dashboard filters (airline and month)
-- ---------------------------------------------------------------------
-- The dashboard lets the user pick an airline and a month. Instead of
-- loading 50,000 flights into Python, SQL aggregates once at the finest
-- grain we need (airline x month x cause, at most 14 x 12 x 5 = 840 rows)
-- and the page only re-sums these few rows for the selected filters.
-- The number of delayed flights cannot be rebuilt from the cause rows
-- (a flight can have several causes), so it has its own view.
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


-- ---------------------------------------------------------------------
-- 8. Findings and recommendations
-- ---------------------------------------------------------------------
-- Context: 9220 delayed flights, 543,220 delay minutes, about 59 minutes
-- per delayed flight.
--
-- Finding 1: two causes dominate.
--   Late aircraft is 39.1% of delay minutes and Airline is 32.3%, so
--   about 71% of the delay comes from the airlines' own operations and
--   from delays passed on by the previous flight of the same aircraft.
--   Recommendation: add turnaround buffer to tight aircraft rotations
--   and measure how a delay spreads along an aircraft's daily flights
--   (tail_number) to see where it starts.
--
-- Finding 2: weather is rare but severe.
--   Weather is only 5.4% of minutes and touches 594 flights, but it has
--   the highest average (49.4 min per flight, against 43.8 for late
--   aircraft). Security is negligible (30 flights, 0.1%).
--   Recommendation: do not spend the effort on security; for weather,
--   plan contingency for the rare large events, since the average hides
--   long delays.
--
-- Finding 3: the cause mix depends on the airline.
--   Southwest has the largest delay total (102,905 min, 18.9% of all)
--   and half of it is late aircraft (50.8%). Delta's biggest cause is
--   its own operations (Airline 42.2%). Spirit (48.5%), Virgin America
--   (42.5%) and Frontier (38.5%) have a high share of air system delays,
--   against 23.1% overall.
--   Recommendation: do not apply one generic fix. Late-aircraft airlines
--   need schedule slack, airline-cause airlines need an internal
--   operations review, and air system delays should be looked at with
--   the airport results (Person 2) to see where congestion happens.
--
-- Limits: shares describe the composition of delays, not how punctual an
-- airline is (that is Person 1's delay rate). Results are for this
-- 50,000-flight sample.
