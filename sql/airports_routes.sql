/*
  Projet : Flight Delays and Cancellations
  Thème  : Airports & Routes
  Fichier: sql/airports_routes.sql

  Hypothèses communes :
  - Un vol est considéré retardé si arrival_delay >= 15 minutes.
  - Population éligible : vols non annulés, non détournés,
    avec arrival_delay renseigné.
  - Seuil minimal : 30 vols éligibles par aéroport ou par route.
  - Les vues analytiques utilisent les codes normalisés et la table airports.
  - Les codes bruts (_raw) sont conservés pour le diagnostic Data Quality.
*/

/* Index pour les statistiques par aéroport de départ */
CREATE INDEX IF NOT EXISTS idx_flights_airport_delays
ON flights (origin_airport)
INCLUDE (arrival_delay)
WHERE cancelled = 0
  AND diverted = 0
  AND arrival_delay IS NOT NULL;


EXPLAIN ANALYZE
SELECT *
FROM flights f
INNER JOIN airports a
    ON f.origin_airport = a.iata_code
WHERE f.cancelled = 0
  AND f.diverted = 0
  AND f.arrival_delay IS NOT NULL;


/* Index pour les statistiques par route */
CREATE INDEX IF NOT EXISTS idx_flights_route_delays
ON flights (origin_airport, destination_airport)
INCLUDE (arrival_delay)
WHERE cancelled = 0
  AND diverted = 0
  AND arrival_delay IS NOT NULL
  AND origin_airport IS NOT NULL
  AND destination_airport IS NOT NULL;

EXPLAIN ANALYZE
SELECT
    origin_airport,
    destination_airport,
    COUNT(*),
    AVG(arrival_delay)
FROM flights
WHERE cancelled = 0
  AND diverted = 0
  AND arrival_delay IS NOT NULL
  AND origin_airport IS NOT NULL
  AND destination_airport IS NOT NULL
GROUP BY origin_airport, destination_airport;

/* ============================================================
   VUE 1 - Statistiques des retards par aéroport de départ
   ============================================================ */

CREATE OR REPLACE VIEW v_airports_routes_airport_delays AS

WITH airport_stats AS (
    SELECT
        f.origin_airport AS airport_code,
        a.airport AS airport_name,
        a.city,
        a.state,

        COUNT(*) AS eligible_flights,

        COUNT(*) FILTER (
            WHERE f.arrival_delay >= 15
        ) AS delayed_flights,

        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE f.arrival_delay >= 15
            ) / COUNT(*),
            2
        ) AS delay_rate_pct,

        ROUND(
            AVG(f.arrival_delay) FILTER (
                WHERE f.arrival_delay >= 15
			),
            2
        ) AS avg_arrival_delay

    FROM flights f

    INNER JOIN airports a
        ON f.origin_airport = a.iata_code

    WHERE f.cancelled = 0
      AND f.diverted = 0
      AND f.arrival_delay IS NOT NULL

    GROUP BY
        f.origin_airport,
        a.airport,
        a.city,
        a.state
	HAVING COUNT(*) >= 30
)

SELECT
    airport_code,
    airport_name,
    city,
    state,
    eligible_flights,
    delayed_flights,
    delay_rate_pct,
    avg_arrival_delay,

    RANK() OVER (
        ORDER BY delayed_flights DESC
    ) AS delay_volume_rank,

    RANK() OVER (
        ORDER BY delay_rate_pct DESC,
		         eligible_flights DESC
    ) AS delay_rate_rank

FROM airport_stats;


/* Résultat complémentaire : Top 10 aéroports par taux de retard */
SELECT *
FROM v_airports_routes_airport_delays
ORDER BY delay_rate_rank
LIMIT 10;

/* Résultat dashboard : Top 10 aéroports par volume de retards */
SELECT *
FROM v_airports_routes_airport_delays
ORDER BY delay_volume_rank
LIMIT 10;


/* ============================================================
   VUE 2 - Analyse des retards par route (origine -> destination)
   ============================================================ */


CREATE OR REPLACE VIEW v_airports_routes_top_routes AS
WITH route_stats AS (
    SELECT
        f.origin_airport AS origin_code,
        ao.airport AS origin_name,
        ao.city AS origin_city,

        f.destination_airport AS destination_code,
        ad.airport AS destination_name,
        ad.city AS destination_city,

        COUNT(*) AS eligible_flights,

        COUNT(*) FILTER (
            WHERE f.arrival_delay >= 15
        ) AS delayed_flights,

        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE f.arrival_delay >= 15
            ) / COUNT(*),
            2
        ) AS delay_rate_pct,

        ROUND(
            AVG(f.arrival_delay) FILTER (
                WHERE f.arrival_delay >= 15
			),
            2
        ) AS avg_arrival_delay

    FROM flights f

    INNER JOIN airports ao
        ON f.origin_airport = ao.iata_code

    INNER JOIN airports ad
        ON f.destination_airport = ad.iata_code

    WHERE f.cancelled = 0
      AND f.diverted = 0
      AND f.arrival_delay IS NOT NULL
      AND f.origin_airport IS NOT NULL
      AND f.destination_airport IS NOT NULL

    GROUP BY
        f.origin_airport, ao.airport, ao.city,
        f.destination_airport, ad.airport, ad.city

    HAVING COUNT(*) >= 30
)

SELECT
    origin_code,
    origin_name,
    origin_city,
    destination_code,
    destination_name,
    destination_city,
    eligible_flights,
    delayed_flights,
    delay_rate_pct,
    avg_arrival_delay,

    ROW_NUMBER() OVER (
        ORDER BY
            delayed_flights DESC,
            delay_rate_pct DESC,
            eligible_flights DESC
    ) AS route_rank

FROM route_stats;

/* Résultat dashboard : Top 10 routes par nombre de vols retardés */
SELECT *
FROM v_airports_routes_top_routes
WHERE route_rank <= 10
ORDER BY route_rank;


/* ============================================================
   DATA QUALITY - Codes d'aéroports bruts non reconnus
   ============================================================ */

/* Codes non correspondants, séparés entre départ et arrivée */

WITH airport_codes AS (
    SELECT
        'Departure' AS airport_role,
        origin_airport_raw AS airport_code
    FROM flights

    UNION ALL

    SELECT
        'Arrival' AS airport_role,
        destination_airport_raw AS airport_code
    FROM flights
)

SELECT
    ac.airport_role,
    ac.airport_code,
    COUNT(*) AS affected_flights

FROM airport_codes ac

LEFT JOIN airports a
    ON ac.airport_code = a.iata_code

WHERE a.iata_code IS NULL

GROUP BY
    ac.airport_role,
    ac.airport_code

ORDER BY
    affected_flights DESC;

/* Nombre de vols distincts ayant au moins un aéroport non reconnu */

SELECT
    COUNT(*) AS total_flights,

    COUNT(*) FILTER (
        WHERE origin_airport IS NULL
           OR destination_airport IS NULL
    ) AS flights_with_unmatched_airport,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE origin_airport IS NULL
               OR destination_airport IS NULL
        ) / COUNT(*),
        2
    ) AS unmatched_flights_pct

FROM flights;