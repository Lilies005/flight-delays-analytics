SELECT a.airline,
       COUNT(*) AS total_flights,
       COUNT(*) FILTER (WHERE f.arrival_delay >= 15) AS delayed_flights,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.arrival_delay >= 15) / COUNT(*), 2) AS delay_rate_pct
FROM flights f
JOIN airlines a ON a.iata_code = f.airline
WHERE f.cancelled = 0 AND f.diverted = 0
GROUP BY a.airline
ORDER BY delay_rate_pct DESC;





SELECT a.airline,
       RANK() OVER (
         ORDER BY 100.0 * COUNT(*) FILTER (WHERE f.arrival_delay >= 15) / COUNT(*) DESC
       ) AS airline_rank,
       ROUND(AVG(f.arrival_delay), 1) AS avg_arrival_delay_min,
       ROUND(AVG(f.arrival_delay) FILTER (WHERE f.arrival_delay >= 15), 1) AS avg_delay_when_late_min
FROM flights f
JOIN airlines a ON a.iata_code = f.airline
WHERE f.cancelled = 0 AND f.diverted = 0
GROUP BY a.airline
ORDER BY airline_rank;