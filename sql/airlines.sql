
-- Vue 1 : vols, vols en retard, taux de retard et retard moyen (vols en retard) par compagnie
CREATE OR REPLACE VIEW v_airlines_delay_rate AS
SELECT a.iata_code,
       a.airline,
       COUNT(*) AS total_flights,
       COUNT(*) FILTER (WHERE f.arrival_delay >= 15) AS delayed_flights,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct,
       ROUND(AVG(f.arrival_delay) FILTER (WHERE f.arrival_delay >= 15), 1) AS avg_delay_when_late_min
FROM flights f
JOIN airlines a ON a.iata_code = f.airline
WHERE f.cancelled = 0
  AND f.diverted = 0
  AND f.arrival_delay IS NOT NULL
GROUP BY a.iata_code, a.airline
HAVING COUNT(*) >= 30;


-- Vue 2 : classement RANK() par taux de retard, avec retards moyens
--   avg_arrival_delay_min   : moyenne sur tous les vols eligibles (les vols en avance comptent en negatif)
--   avg_delay_when_late_min : moyenne sur les seuls vols en retard
CREATE OR REPLACE VIEW v_airlines_ranking AS
SELECT a.iata_code,
       a.airline,
       RANK() OVER (
         ORDER BY 100.0 * COUNT(*) FILTER (WHERE f.arrival_delay >= 15) / COUNT(*) DESC
       ) AS airline_rank,
       COUNT(*) AS total_flights,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct,
       ROUND(AVG(f.arrival_delay), 1) AS avg_arrival_delay_min,
       ROUND(AVG(f.arrival_delay) FILTER (WHERE f.arrival_delay >= 15), 1) AS avg_delay_when_late_min
FROM flights f
JOIN airlines a ON a.iata_code = f.airline
WHERE f.cancelled = 0
  AND f.diverted = 0
  AND f.arrival_delay IS NOT NULL
GROUP BY a.iata_code, a.airline
HAVING COUNT(*) >= 30;


-- Open issue : fiabilite du taux selon le nombre de vols.
-- Le seuil de 30 vols (regle commune) ecarte seulement les groupes minuscules ;
-- ici toutes les compagnies le depassent. On ajoute donc une marge d'erreur (intervalle
-- a 95 %) et un indicateur "reliable" (>= 1000 vols).
CREATE OR REPLACE VIEW v_airlines_reliability AS
SELECT a.iata_code,
       a.airline,
       COUNT(*) AS total_flights,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct,
       ROUND(196 * SQRT(
         (COUNT(*) FILTER (WHERE f.arrival_delay >= 15))::numeric / COUNT(*)
         * (1 - (COUNT(*) FILTER (WHERE f.arrival_delay >= 15))::numeric / COUNT(*))
         / COUNT(*)), 1) AS margin_pts,
       COUNT(*) >= 1000 AS reliable
FROM flights f
JOIN airlines a ON a.iata_code = f.airline
WHERE f.cancelled = 0
  AND f.diverted = 0
  AND f.arrival_delay IS NOT NULL
GROUP BY a.iata_code, a.airline
HAVING COUNT(*) >= 30;


-- Diagnostic qualite des donnees (une seule ligne)
--   missing_arrival_delay : vols eligibles sans arrival_delay (attendu : 0)
--   unmatched_airline_codes : codes compagnie de flights_raw absents de airlines (attendu : 0)
CREATE OR REPLACE VIEW v_airlines_data_quality AS
SELECT
  (SELECT COUNT(*) FROM flights) AS total_flights,
  (SELECT COUNT(*) FROM flights WHERE cancelled = 1) AS cancelled_flights,
  (SELECT COUNT(*) FROM flights WHERE diverted = 1) AS diverted_flights,
  (SELECT COUNT(*) FROM flights WHERE cancelled = 0 AND diverted = 0) AS not_cancelled_not_diverted,
  (SELECT COUNT(*) FROM flights
    WHERE cancelled = 0 AND diverted = 0 AND arrival_delay IS NULL) AS missing_arrival_delay,
  (SELECT COUNT(*) FROM flights_raw r
    LEFT JOIN airlines a ON a.iata_code = r.airline
    WHERE a.iata_code IS NULL) AS unmatched_airline_codes;


-- Lecture des vues (l'ordre se donne ici, pas dans la vue)
-- SELECT * FROM v_airlines_delay_rate ORDER BY delay_rate_pct DESC;
-- SELECT * FROM v_airlines_ranking ORDER BY airline_rank;
-- SELECT * FROM v_airlines_reliability ORDER BY delay_rate_pct DESC;
-- SELECT * FROM v_airlines_data_quality;