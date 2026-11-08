-- 00_setup_database.sql : cree les tables
-- A lancer depuis la RACINE du projet, sur une base vide :
--   psql -d flights_db -f sql/00_setup_database.sql

-- ========== PARTIE 1 : CREATION DES TABLES ==========

DROP TABLE IF EXISTS flights CASCADE;
DROP TABLE IF EXISTS flights_raw CASCADE;
DROP TABLE IF EXISTS cancellation_reasons CASCADE;
DROP TABLE IF EXISTS airports CASCADE;
DROP TABLE IF EXISTS airlines CASCADE;

CREATE TABLE airlines (
  iata_code TEXT PRIMARY KEY,
  airline   TEXT
);

CREATE TABLE airports (
  iata_code TEXT PRIMARY KEY,
  airport   TEXT,
  city      TEXT,
  state     TEXT,
  country   TEXT,
  latitude  NUMERIC,
  longitude NUMERIC
);

CREATE TABLE cancellation_reasons (
  code   TEXT PRIMARY KEY,
  reason TEXT NOT NULL
);

-- Table de passage : les 31 colonnes du CSV, tout en texte
CREATE TABLE flights_raw (
  year TEXT, month TEXT, day TEXT, day_of_week TEXT, airline TEXT,
  flight_number TEXT, tail_number TEXT, origin_airport TEXT, destination_airport TEXT,
  scheduled_departure TEXT, departure_time TEXT, departure_delay TEXT, taxi_out TEXT,
  wheels_off TEXT, scheduled_time TEXT, elapsed_time TEXT, air_time TEXT, distance TEXT,
  wheels_on TEXT, taxi_in TEXT, scheduled_arrival TEXT, arrival_time TEXT, arrival_delay TEXT,
  diverted TEXT, cancelled TEXT, cancellation_reason TEXT,
  air_system_delay TEXT, security_delay TEXT, airline_delay TEXT,
  late_aircraft_delay TEXT, weather_delay TEXT
);

-- Table propre : types, cles etrangeres, colonnes ajoutees
CREATE TABLE flights (
  flight_id                BIGSERIAL PRIMARY KEY,
  flight_date              DATE     NOT NULL,
  year                     SMALLINT NOT NULL,
  month                    SMALLINT NOT NULL,
  day                      SMALLINT NOT NULL,
  day_of_week              SMALLINT NOT NULL,
  airline                  TEXT     NOT NULL REFERENCES airlines(iata_code),
  flight_number            INT,
  tail_number              TEXT,
  origin_airport           TEXT REFERENCES airports(iata_code),   -- NULL si code numerique
  destination_airport      TEXT REFERENCES airports(iata_code),   -- NULL si code numerique
  origin_airport_raw       TEXT     NOT NULL,
  destination_airport_raw  TEXT     NOT NULL,
  scheduled_departure      SMALLINT NOT NULL,
  scheduled_hour           SMALLINT NOT NULL,
  departure_time           SMALLINT,
  departure_delay          INT,
  taxi_out                 INT,
  wheels_off               SMALLINT,
  scheduled_time           INT,
  elapsed_time             INT,
  air_time                 INT,
  distance                 INT,
  wheels_on                SMALLINT,
  taxi_in                  INT,
  scheduled_arrival        SMALLINT,
  arrival_time             SMALLINT,
  arrival_delay            INT,
  diverted                 SMALLINT NOT NULL CHECK (diverted  IN (0,1)),
  cancelled                SMALLINT NOT NULL CHECK (cancelled IN (0,1)),
  cancellation_reason      TEXT REFERENCES cancellation_reasons(code),
  air_system_delay         INT,
  security_delay           INT,
  airline_delay            INT,
  late_aircraft_delay      INT,
  weather_delay            INT
);

CREATE INDEX idx_flights_airline ON flights(airline);
CREATE INDEX idx_flights_origin  ON flights(origin_airport);
CREATE INDEX idx_flights_dest    ON flights(destination_airport);
CREATE INDEX idx_flights_month   ON flights(month);