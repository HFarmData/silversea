-- =============================================================================
-- EJ — ANALISI POST SUITE SELECTION (una riga per utente)
-- =============================================================================
-- Punto di partenza: primo Suite Selection dell'utente (page_view, URL /booking?step=suites).
-- Estrae: p_journey_code dello step, 10 touchpoint successivi (pv_1..pv_10), pv_0 = URL del SS,
-- e flag 0/1 (RAC, RAQ, Brochure, BH, Purchase, reingresso viaggio diverso).
-- Tutto scoped alla STESSA sessione (ga_session_id) e DOPO il timestamp del Suite Selection.
-- Esclusi gli utenti con URL 'my-explora' nella stessa sessione PRIMA del Suite Selection.
-- =============================================================================

WITH base_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id')       AS ga_session_id,
    event_timestamp,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')        AS page_url,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_journey_code')        AS p_journey_code,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'lead_name')             AS lead_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'payment_type')          AS payment_type,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'booking_status')        AS booking_status,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_journey_is_destex')   AS p_journey_is_destex
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX BETWEEN 'AAAAMMGG' AND 'AAAAMMGG'   -- << IMPOSTA PERIODO (es. 20260402 - 20260414)
),

-- STEP 1: primo Suite Selection per utente (grezzo, prima dell'esclusione my-explora)
suite_selection AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    event_timestamp AS ss_timestamp,
    page_url        AS ss_page_url,
    p_journey_code  AS ss_journey_code,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp ASC) AS rn
  FROM base_events
  WHERE event_name = 'page_view'
    AND page_url LIKE '%/booking?step=suites%'
),

first_suite_raw AS (
  SELECT user_pseudo_id, ga_session_id, ss_timestamp, ss_page_url, ss_journey_code
  FROM suite_selection
  WHERE rn = 1
),

-- STEP 2: utenti da escludere -> 'my-explora' nella stessa sessione, PRIMA del Suite Selection
users_to_exclude AS (
  SELECT DISTINCT fsr.user_pseudo_id
  FROM first_suite_raw fsr
  JOIN base_events b
    ON  b.user_pseudo_id = fsr.user_pseudo_id
    AND b.ga_session_id  = fsr.ga_session_id
    AND b.event_timestamp < fsr.ss_timestamp
  WHERE LOWER(b.page_url) LIKE '%my-explora%'
),

first_suite AS (
  SELECT fsr.*
  FROM first_suite_raw fsr
  WHERE NOT EXISTS (
    SELECT 1 FROM users_to_exclude ux WHERE ux.user_pseudo_id = fsr.user_pseudo_id
  )
),

-- STEP 3: touchpoint successivi (page_view + RAC/RAQ/Brochure/BH), stessa sessione, dopo il SS
subsequent_pvs AS (
  SELECT
    fs.user_pseudo_id,
    ROW_NUMBER() OVER (PARTITION BY fs.user_pseudo_id ORDER BY b.event_timestamp ASC) AS pv_rank,
    -- valore mostrato: etichetta per gli eventi azione, URL per i page_view
    CASE
      WHEN b.event_name = 'request_call_back_confirmation' THEN 'RAC'
      WHEN b.event_name = 'request_quote_confirmation'     THEN 'RAQ'
      WHEN b.event_name = 'request_brochure_confirmation'  THEN 'Brochure'
      WHEN b.event_name = 'generate_lead'
        AND b.lead_name = 'booking' AND b.payment_type = 'free' AND b.booking_status = 'option' THEN 'BH'
      ELSE b.page_url
    END AS pv_value
  FROM first_suite fs
  INNER JOIN base_events b
    ON  b.user_pseudo_id = fs.user_pseudo_id
    AND b.ga_session_id  = fs.ga_session_id
    AND b.event_timestamp > fs.ss_timestamp
  WHERE b.event_name = 'page_view'
     OR b.event_name = 'request_call_back_confirmation'
     OR b.event_name = 'request_quote_confirmation'
     OR b.event_name = 'request_brochure_confirmation'
     OR (b.event_name = 'generate_lead'
         AND b.lead_name = 'booking' AND b.payment_type = 'free' AND b.booking_status = 'option')
  QUALIFY pv_rank <= 10
),

-- STEP 4: pivot dei 10 touchpoint
pvs_pivoted AS (
  SELECT
    user_pseudo_id,
    MAX(IF(pv_rank = 1,  pv_value, NULL)) AS pv_1,
    MAX(IF(pv_rank = 2,  pv_value, NULL)) AS pv_2,
    MAX(IF(pv_rank = 3,  pv_value, NULL)) AS pv_3,
    MAX(IF(pv_rank = 4,  pv_value, NULL)) AS pv_4,
    MAX(IF(pv_rank = 5,  pv_value, NULL)) AS pv_5,
    MAX(IF(pv_rank = 6,  pv_value, NULL)) AS pv_6,
    MAX(IF(pv_rank = 7,  pv_value, NULL)) AS pv_7,
    MAX(IF(pv_rank = 8,  pv_value, NULL)) AS pv_8,
    MAX(IF(pv_rank = 9,  pv_value, NULL)) AS pv_9,
    MAX(IF(pv_rank = 10, pv_value, NULL)) AS pv_10
  FROM subsequent_pvs
  GROUP BY user_pseudo_id
),

-- STEP 5: flag azioni post Suite Selection (stessa sessione, in tutta la visita post-SS)
flags AS (
  SELECT
    fs.user_pseudo_id,
    MAX(CASE WHEN b.event_name = 'request_call_back_confirmation' THEN 1 ELSE 0 END) AS flag_rac,
    MAX(CASE WHEN b.event_name = 'request_quote_confirmation'     THEN 1 ELSE 0 END) AS flag_raq,
    MAX(CASE WHEN b.event_name = 'request_brochure_confirmation'  THEN 1 ELSE 0 END) AS flag_brochure,
    MAX(CASE
      WHEN b.event_name = 'generate_lead'
        AND b.lead_name = 'booking' AND b.payment_type = 'free' AND b.booking_status = 'option'
      THEN 1 ELSE 0 END) AS flag_bh,
    MAX(CASE
      WHEN b.event_name = 'purchase'
        AND b.p_journey_is_destex = 'NO' AND b.payment_type != 'total'
      THEN 1 ELSE 0 END) AS flag_purchase,
    MAX(CASE
      WHEN b.event_name = 'begin_checkout'
        AND b.p_journey_code IS NOT NULL AND b.p_journey_code != fs.ss_journey_code
      THEN 1 ELSE 0 END) AS flag_reingresso_viaggio_diverso
  FROM first_suite fs
  INNER JOIN base_events b
    ON  b.user_pseudo_id = fs.user_pseudo_id
    AND b.ga_session_id  = fs.ga_session_id
    AND b.event_timestamp > fs.ss_timestamp
  GROUP BY fs.user_pseudo_id
)

-- OUTPUT FINALE: una riga per utente
SELECT
  fs.user_pseudo_id,
  fs.ss_journey_code,
  TIMESTAMP_MICROS(fs.ss_timestamp) AS suite_selection_timestamp,
  fs.ss_page_url AS pv_0,
  pv.pv_1, pv.pv_2, pv.pv_3, pv.pv_4, pv.pv_5,
  pv.pv_6, pv.pv_7, pv.pv_8, pv.pv_9, pv.pv_10,
  COALESCE(f.flag_rac, 0)                        AS flag_rac,
  COALESCE(f.flag_raq, 0)                        AS flag_raq,
  COALESCE(f.flag_brochure, 0)                   AS flag_brochure,
  COALESCE(f.flag_bh, 0)                         AS flag_bh,
  COALESCE(f.flag_purchase, 0)                   AS flag_purchase,
  COALESCE(f.flag_reingresso_viaggio_diverso, 0) AS flag_reingresso_viaggio_diverso
FROM first_suite fs
LEFT JOIN pvs_pivoted pv ON pv.user_pseudo_id = fs.user_pseudo_id
LEFT JOIN flags f        ON f.user_pseudo_id  = fs.user_pseudo_id
ORDER BY fs.ss_timestamp;
