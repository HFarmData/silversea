-- =============================================================================
-- EJ — GIORNI DI ANTICIPO VS PARTENZA: GLOBALE per page group
-- =============================================================================
-- Itinerary Page vs Funnel: media e mediana dei giorni tra la visita e la partenza.
-- Gestione doppio formato data + CASE con Funnel valutato PRIMA della Itinerary Page.
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
    visit_date,
    -- doppio formato: yyyy-MM-dd (sito) oppure dd-MM-yyyy (booking engine)
    CASE
      WHEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure)
      WHEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure)
    END AS departure_date,
    -- Funnel PRIMA di Itinerary Page (gli URL del funnel contengono anche journeys/)
    CASE
      WHEN page_url LIKE '%booking.explorajourneys.com/touchb2c%' THEN 'Funnel'
      WHEN page_url LIKE '%journeys/%'
           AND NOT REGEXP_CONTAINS(page_url, r'my-explora|about') THEN 'Itinerary Page'
    END AS page_group
  FROM base
)

SELECT
  page_group,
  COUNT(*) AS total_pageviews,
  ROUND(AVG(DATE_DIFF(departure_date, visit_date, DAY)), 1) AS avg_days_before_departure,
  ROUND(CAST(APPROX_QUANTILES(DATE_DIFF(departure_date, visit_date, DAY), 100)[OFFSET(50)] AS FLOAT64), 1) AS median_days_before_departure
FROM classified
WHERE page_group IS NOT NULL
  AND departure_date IS NOT NULL
GROUP BY page_group
ORDER BY page_group;
