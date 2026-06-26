-- =============================================================================
-- EJ — A/B TEST "19_continue_where_you_left_v2" (popup return-to-funnel)
-- =============================================================================
-- Metriche per variante: funnel entry, booking hold, purchase, click popup,
-- in versione GENERALE e POST-POPUP (solo azioni dopo il primo popup visto).
-- Esclusi gli utenti esposti a piu' varianti. Campione opzionale 4k/variante.
-- =============================================================================

WITH

-- 0) Utenti "contaminati": esposti a piu' di una variante -> da escludere
users_multi_variation AS (
  SELECT user_pseudo_id
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260131' AND '20260301'   -- << IMPOSTA PERIODO
    AND event_name = 'experiment_viewed'
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'experiment_id') = '19_continue_where_you_left_v2'
    AND user_pseudo_id IS NOT NULL
  GROUP BY user_pseudo_id
  HAVING COUNT(DISTINCT
    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'variation_id')
  ) > 1
),

-- 1) Utenti nell'esperimento (mono-variante)
experiment_users AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'variation_id') AS variation_id
  FROM `ejattribution.analytics_268301381.events_*` e
  WHERE _TABLE_SUFFIX BETWEEN '20260131' AND '20260301'
    AND event_name = 'experiment_viewed'
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'experiment_id') = '19_continue_where_you_left_v2'
    AND user_pseudo_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM users_multi_variation umv WHERE umv.user_pseudo_id = e.user_pseudo_id
    )
),

-- 1b) (OPZIONALE) Campione deterministico 4k utenti per variante
--     Per usarlo: sostituire 'experiment_users' con 'experiment_sample' nelle CTE successive.
experiment_sample AS (
  SELECT user_pseudo_id, variation_id
  FROM (
    SELECT
      user_pseudo_id, variation_id,
      ROW_NUMBER() OVER (PARTITION BY variation_id ORDER BY FARM_FINGERPRINT(user_pseudo_id)) AS rn
    FROM experiment_users
  )
  WHERE rn <= 4000
),

-- 2) Utenti che hanno VISTO il popup, con primo timestamp
popup_seen_users AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS popup_seen_timestamp
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260131' AND '20260301'
    AND event_name = 'content_cta'
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'cta_name') = 'popup_funnel'
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'cta_type') = 'popup_seen'
    AND user_pseudo_id IS NOT NULL
  GROUP BY user_pseudo_id
),

-- 3) Utenti dell'esperimento che hanno visto il popup, con variante e timestamp popup
cluster_users AS (
  SELECT eu.user_pseudo_id, eu.variation_id, psu.popup_seen_timestamp
  FROM experiment_users eu               -- << per il campione: usare experiment_sample
  INNER JOIN popup_seen_users psu
    ON eu.user_pseudo_id = psu.user_pseudo_id
),

-- 4) Eventi degli utenti del cluster (con timestamp e campi rilevanti)
user_events AS (
  SELECT
    e.user_pseudo_id,
    e.event_timestamp,
    e.event_name,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'page_location') AS raw_url,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'lead_name')      AS lead_name,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'payment_type')   AS payment_type,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'p_journey_is_destex') AS p_journey_is_destex,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'cta_name')       AS cta_name
  FROM `ejattribution.analytics_268301381.events_*` e
  WHERE _TABLE_SUFFIX BETWEEN '20260131' AND '20260301'
    AND e.user_pseudo_id IN (SELECT user_pseudo_id FROM cluster_users)
),

-- 5) Flag per utente: GENERALI e POST-POPUP
user_flags AS (
  SELECT
    cu.user_pseudo_id,
    cu.variation_id,

    -- GENERALI
    MAX(CASE WHEN ue.raw_url LIKE '%booking.explorajourneys.com/touchb2c/%' THEN 1 ELSE 0 END) AS has_funnel_entry,
    MAX(CASE WHEN ue.event_name = 'generate_lead' AND ue.lead_name = 'booking' THEN 1 ELSE 0 END) AS has_booking_hold,
    MAX(CASE WHEN ue.event_name = 'purchase' AND ue.p_journey_is_destex = 'NO'
              AND COALESCE(ue.payment_type, '') != 'total' THEN 1 ELSE 0 END) AS has_purchase,
    MAX(CASE WHEN ue.event_name = 'content_cta' AND ue.cta_name = 'return_to_funnel' THEN 1 ELSE 0 END) AS has_click_popup,

    -- POST-POPUP (solo azioni dopo il primo popup visto)
    MAX(CASE WHEN ue.event_name = 'generate_lead' AND ue.lead_name = 'booking'
              AND ue.event_timestamp > cu.popup_seen_timestamp THEN 1 ELSE 0 END) AS has_booking_hold_post_popup,
    MAX(CASE WHEN ue.event_name = 'purchase' AND ue.p_journey_is_destex = 'NO'
              AND COALESCE(ue.payment_type, '') != 'total'
              AND ue.event_timestamp > cu.popup_seen_timestamp THEN 1 ELSE 0 END) AS has_purchase_post_popup,
    MAX(CASE WHEN ue.event_name = 'content_cta' AND ue.cta_name = 'return_to_funnel'
              AND ue.event_timestamp > cu.popup_seen_timestamp THEN 1 ELSE 0 END) AS has_click_popup_post_popup
  FROM cluster_users cu
  LEFT JOIN user_events ue ON cu.user_pseudo_id = ue.user_pseudo_id
  GROUP BY cu.user_pseudo_id, cu.variation_id
)

-- OUTPUT: aggregato per variante
SELECT
  variation_id,
  COUNT(*) AS utenti_popup_visto,

  -- generali
  SUM(has_funnel_entry) AS funnel_entry,
  SUM(has_booking_hold) AS booking_hold,
  SUM(has_purchase)     AS purchase,
  SUM(has_click_popup)  AS click_popup,
  SUM(CASE WHEN has_click_popup = 1 AND has_booking_hold = 1 THEN 1 ELSE 0 END) AS click_popup_then_bh,
  SUM(CASE WHEN has_click_popup = 1 AND has_purchase = 1     THEN 1 ELSE 0 END) AS click_popup_then_purchase,

  -- post-popup
  SUM(has_booking_hold_post_popup) AS booking_hold_post_popup,
  SUM(has_purchase_post_popup)     AS purchase_post_popup,
  SUM(has_click_popup_post_popup)  AS click_popup_post_popup,
  SUM(CASE WHEN has_click_popup_post_popup = 1 AND has_booking_hold_post_popup = 1 THEN 1 ELSE 0 END) AS click_then_bh_post_popup,
  SUM(CASE WHEN has_click_popup_post_popup = 1 AND has_purchase_post_popup = 1     THEN 1 ELSE 0 END) AS click_then_purchase_post_popup
FROM user_flags
GROUP BY variation_id
ORDER BY variation_id;
