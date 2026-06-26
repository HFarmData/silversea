-- =============================================================================
-- EJ — DISTRIBUZIONE A FASCE dei giorni di anticipo, per page group
-- =============================================================================
-- Curva di come si distribuiscono i giorni tra visita e partenza.
-- Fasce con prefisso numerico per ordinamento. Le fasce negative = visita DOPO la partenza.
-- =============================================================================

WITH base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS visit_date,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_departure_date') AS raw_departure,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')    AS page_url
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250325' AND '20260325'   -- << IMPOSTA PERIODO
    AND event_name = 'page_view'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_departure_date') IS NOT NULL
),

classified AS (
  SELECT
    DATE_DIFF(
      CASE
        WHEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure)
        WHEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure)
      END,
      visit_date, DAY) AS days_before,
    CASE
      WHEN page_url LIKE '%booking.explorajourneys.com/touchb2c%' THEN 'Funnel'
      WHEN page_url LIKE '%journeys/%'
           AND NOT REGEXP_CONTAINS(page_url, r'my-explora|about') THEN 'Itinerary Page'
    END AS page_group
  FROM base
)

SELECT
  page_group,
  CASE
    WHEN days_before < 0          THEN '0 - Dopo la partenza'
    WHEN days_before = 0          THEN '1 - Giorno di partenza'
    WHEN days_before BETWEEN 1 AND 7     THEN '2 - 1-7 giorni'
    WHEN days_before BETWEEN 8 AND 30    THEN '3 - 8-30 giorni'
    WHEN days_before BETWEEN 31 AND 90   THEN '4 - 31-90 giorni'
    WHEN days_before BETWEEN 91 AND 180  THEN '5 - 91-180 giorni'
    WHEN days_before BETWEEN 181 AND 365 THEN '6 - 181-365 giorni'
    ELSE '7 - 365+ giorni'
  END AS days_bucket,
  COUNT(*) AS total_pageviews
FROM classified
WHERE page_group IS NOT NULL
  AND days_before IS NOT NULL
GROUP BY page_group, days_bucket
ORDER BY page_group, days_bucket;
