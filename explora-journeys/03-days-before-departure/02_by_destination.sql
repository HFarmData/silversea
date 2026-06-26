-- =============================================================================
-- EJ — GIORNI DI ANTICIPO VS PARTENZA: per DESTINAZIONE (p_sub_category)
-- =============================================================================
-- p_sub_category = macro destinazione (es. 'car' = Caraibi).
-- Sulle pagine FUNNEL p_sub_category NON e' tracciata: si eredita dall'ultima
-- Itinerary Page vista dallo stesso utente, prima a livello SESSIONE, poi UTENTE.
-- =============================================================================

WITH base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id')     AS ga_session_id,
    event_timestamp,
    PARSE_DATE('%Y%m%d', event_date) AS visit_date,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_departure_date')   AS raw_departure,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')      AS page_url,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_sub_category')     AS p_sub_category
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250325' AND '20260325'   -- << IMPOSTA PERIODO
    AND event_name = 'page_view'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_departure_date') IS NOT NULL
),

classified AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    event_timestamp,
    visit_date,
    CASE
      WHEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure)
      WHEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure)
    END AS departure_date,
    CASE
      WHEN page_url LIKE '%booking.explorajourneys.com/touchb2c%' THEN 'Funnel'
      WHEN page_url LIKE '%journeys/%'
           AND NOT REGEXP_CONTAINS(page_url, r'my-explora|about') THEN 'Itinerary Page'
    END AS page_group,
    p_sub_category
  FROM base
),

-- Ultima Itinerary Page per SESSIONE (per ereditare la destinazione sul Funnel)
last_itin_session AS (
  SELECT user_pseudo_id, ga_session_id, p_sub_category AS sub_category_session
  FROM (
    SELECT
      user_pseudo_id, ga_session_id, p_sub_category,
      ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp DESC) AS rn
    FROM classified
    WHERE page_group = 'Itinerary Page' AND p_sub_category IS NOT NULL
  )
  WHERE rn = 1
),

-- Ultima Itinerary Page per UTENTE (fallback cross-session)
last_itin_user AS (
  SELECT user_pseudo_id, p_sub_category AS sub_category_user
  FROM (
    SELECT
      user_pseudo_id, p_sub_category,
      ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp DESC) AS rn
    FROM classified
    WHERE page_group = 'Itinerary Page' AND p_sub_category IS NOT NULL
  )
  WHERE rn = 1
),

with_destination AS (
  SELECT
    c.page_group,
    c.visit_date,
    c.departure_date,
    -- Itinerary: usa la propria; Funnel: eredita da sessione, poi da utente
    COALESCE(
      CASE WHEN c.page_group = 'Itinerary Page' THEN c.p_sub_category END,
      lis.sub_category_session,
      liu.sub_category_user
    ) AS final_sub_category
  FROM classified c
  LEFT JOIN last_itin_session lis
    ON c.user_pseudo_id = lis.user_pseudo_id AND c.ga_session_id = lis.ga_session_id
  LEFT JOIN last_itin_user liu
    ON c.user_pseudo_id = liu.user_pseudo_id
  WHERE c.page_group IS NOT NULL
    AND c.departure_date IS NOT NULL
)

SELECT
  page_group,
  final_sub_category,
  COUNT(*) AS total_pageviews,
  ROUND(AVG(DATE_DIFF(departure_date, visit_date, DAY)), 1) AS avg_days_before_departure,
  ROUND(CAST(APPROX_QUANTILES(DATE_DIFF(departure_date, visit_date, DAY), 100)[OFFSET(50)] AS FLOAT64), 1) AS median_days_before_departure
FROM with_destination
WHERE final_sub_category IS NOT NULL   -- escludi righe senza destinazione ereditabile
GROUP BY page_group, final_sub_category
ORDER BY page_group, total_pageviews DESC;
