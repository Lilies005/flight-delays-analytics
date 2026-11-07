-- ========== PARTIE 2 : CHARGEMENT DES DONNEES ==========

-- 1. Tables de reference (CSV de Kaggle)
\copy airlines FROM 'data/airlines.csv' WITH (FORMAT csv, HEADER true)
\copy airports FROM 'data/airports.csv' WITH (FORMAT csv, HEADER true)

-- 2. Raisons d'annulation (legende Kaggle ; N et UNKNOWN sont les notres)
INSERT INTO cancellation_reasons (code, reason) VALUES
  ('A', 'Airline / Carrier'),
  ('B', 'Weather'),
  ('C', 'National Air System'),
  ('D', 'Security'),
  ('N', 'Not cancelled'),
  ('UNKNOWN', 'Unknown reason');

-- 3. Vols : chargement brut
\copy flights_raw FROM 'data/flights_sample.csv' WITH (FORMAT csv, HEADER true)

-- 4. Table propre flights
INSERT INTO flights (
  flight_date, year, month, day, day_of_week, airline, flight_number, tail_number,
  origin_airport, destination_airport, origin_airport_raw, destination_airport_raw,
  scheduled_departure, scheduled_hour,
  departure_time, departure_delay, taxi_out, wheels_off, scheduled_time, elapsed_time,
  air_time, distance, wheels_on, taxi_in, scheduled_arrival, arrival_time, arrival_delay,
  diverted, cancelled, cancellation_reason,
  air_system_delay, security_delay, airline_delay, late_aircraft_delay, weather_delay
)
SELECT
  make_date(year::int, month::int, day::int), year::int, month::int, day::int, day_of_week::int,
  airline, NULLIF(flight_number,'')::int, NULLIF(tail_number,''),
  CASE WHEN origin_airport      ~ '^[A-Z]{3}$' THEN origin_airport      END,
  CASE WHEN destination_airport ~ '^[A-Z]{3}$' THEN destination_airport END,
  origin_airport, destination_airport,
  scheduled_departure::int, (scheduled_departure::int / 100) % 24,
  NULLIF(departure_time,'')::int, NULLIF(departure_delay,'')::int, NULLIF(taxi_out,'')::int,
  NULLIF(wheels_off,'')::int, NULLIF(scheduled_time,'')::int, NULLIF(elapsed_time,'')::int,
  NULLIF(air_time,'')::int, NULLIF(distance,'')::int, NULLIF(wheels_on,'')::int,
  NULLIF(taxi_in,'')::int, NULLIF(scheduled_arrival,'')::int, NULLIF(arrival_time,'')::int,
  NULLIF(arrival_delay,'')::int,
  diverted::int, cancelled::int, NULLIF(cancellation_reason,''),
  NULLIF(air_system_delay,'')::int, NULLIF(security_delay,'')::int, NULLIF(airline_delay,'')::int,
  NULLIF(late_aircraft_delay,'')::int, NULLIF(weather_delay,'')::int
FROM flights_raw;

-- 5. Controle : comptages a copier dans docs/data_source_and_sampling.md
SELECT 'airlines' AS table_name, COUNT(*) AS nb_lignes FROM airlines
UNION ALL SELECT 'airports', COUNT(*) FROM airports
UNION ALL SELECT 'cancellation_reasons', COUNT(*) FROM cancellation_reasons
UNION ALL SELECT 'flights_raw', COUNT(*) FROM flights_raw
UNION ALL SELECT 'flights', COUNT(*) FROM flights;