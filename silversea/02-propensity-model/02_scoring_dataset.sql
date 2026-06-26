-- =============================================================================
-- SILVERSEA PROPENSITY — SCORING DATASET v3   [RICOSTRUITO dalla specifica]
-- =============================================================================
-- ATTENZIONE: questo builder e' RICOSTRUITO dalla specifica v3 (il file originale
-- era un documento separato). Struttura CTE e feature IDENTICHE a
-- 01_training_dataset.sql: cambiano solo gli ANCHOR (giornalieri, Aprile 2025) e
-- il range _TABLE_SUFFIX. I pattern "-- << CONFERMARE" valgono come nel training.
--
-- Anchor: GIORNALIERI Aprile 2025. Observation window: 30 gg precedenti.
-- Prediction window: 14 gg successivi. Target: generate_lead_WBOF_01.
-- _TABLE_SUFFIX: 20250302 - 20250513 (osservazione mar -> target meta' mag).
-- Output: una riga per (user_pseudo_id, anchor_date) con visits_30d > 0,
--         comprensivo di target_conversion (serve per ML.EVALUATE out-of-time).
-- =============================================================================

CREATE OR REPLACE TABLE `dm-2021-hdm-01.Silversea_Playground.propensity_scoring_apr_2025_v3` AS

WITH

-- 1) Date di riferimento (anchor) GIORNALIERE (Aprile 2025)
anchor_dates AS (
  SELECT anchor_date
  FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE 'AAAA-MM-GG',   -- << anchor start (originale 2025-04-01)
    DATE 'AAAA-MM-GG',   -- << anchor end   (originale 2025-04-30)
    INTERVAL 1 DAY
  )) AS anchor_date
),

-- 2) Eventi nella OBSERVATION WINDOW (30 gg prima dell'anchor), per ogni anchor
--    NB: il CROSS JOIN anchor x eventi e' costoso; restringere _TABLE_SUFFIX.
events AS (
  SELECT
    a.anchor_date,
    e.user_pseudo_id,
    e.event_timestamp,
    PARSE_DATE('%Y%m%d', e.event_date) AS event_date,
    e.event_name,
    (SELECT ep.value.int_value    FROM UNNEST(e.event_params) ep WHERE ep.key = 'ga_session_id') AS ga_session_id,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'page_location')  AS page_url,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'raw_url')         AS raw_url,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'market')          AS market  -- << CONFERMARE sorgente market (param o geo)
  FROM `silversea-293815.analytics_256550454.events_*` e
  CROSS JOIN anchor_dates a
  WHERE _TABLE_SUFFIX BETWEEN '20250302' AND '20250513'   -- << copre anchor + 14gg
    AND e.user_pseudo_id IS NOT NULL
    AND PARSE_DATE('%Y%m%d', e.event_date)
        BETWEEN DATE_SUB(a.anchor_date, INTERVAL 30 DAY) AND DATE_SUB(a.anchor_date, INTERVAL 1 DAY)
),

-- 3) Classificazione pagina/evento (pattern Silversea -> CONFERMARE)
events_with_pages AS (
  SELECT
    *,
    -- VS vs non-VS (provenienza)
    (LOWER(COALESCE(raw_url, '')) LIKE '%utm_medium=email%' AND COALESCE(raw_url, '') LIKE '%_VS_%') AS is_vs,
    -- pagine contenuto
    (page_url LIKE '%/cruises/%')        AS is_itinerary_page,   -- << CONFERMARE pattern itinerary
    (page_url LIKE '%/destinations/%')   AS is_destination_page, -- << CONFERMARE pattern destination
    -- quote / guests-info
    (page_url LIKE '%quote.silversea.com%')                                  AS is_quote_page,
    (page_url LIKE '%quote.silversea.com%' AND page_url LIKE '%/guests-info%') AS is_guests_info,
    -- filtri Find Your Cruise
    (event_name = 'find_your_cruise_filter')  AS is_fyc_filter,  -- << CONFERMARE evento/param FYC
    -- id itinerario / destinazione (per max_same e multi_*)
    REGEXP_EXTRACT(page_url, r'/cruises/([^/?]+)')       AS itinerary_id,    -- << CONFERMARE estrazione id
    REGEXP_EXTRACT(page_url, r'/destinations/([^/?]+)')  AS destination_id   -- << CONFERMARE estrazione id
  FROM events
),

-- 4) Utenti attivi per anchor (almeno un evento in observation window)
active_users_per_anchor AS (
  SELECT DISTINCT anchor_date, user_pseudo_id
  FROM events_with_pages
),

-- 5) Provenienza VS / non-VS (conteggio sessioni)
vs_flags AS (
  SELECT
    anchor_date, user_pseudo_id,
    COUNT(DISTINCT IF(is_vs, ga_session_id, NULL))     AS visits_vs_count,
    COUNT(DISTINCT IF(NOT is_vs, ga_session_id, NULL)) AS visits_no_vs_count
  FROM events_with_pages
  GROUP BY anchor_date, user_pseudo_id
),

-- 6) Market (ultimo valore non nullo nell'observation window)
market_feature AS (
  SELECT anchor_date, user_pseudo_id, market
  FROM (
    SELECT anchor_date, user_pseudo_id, market,
           ROW_NUMBER() OVER (PARTITION BY anchor_date, user_pseudo_id ORDER BY event_timestamp DESC) AS rn
    FROM events_with_pages WHERE market IS NOT NULL
  ) WHERE rn = 1
),

-- 7) Frequenza visite (sessioni distinte) a 7/14/30 gg + pagine totali
visits_features AS (
  SELECT
    anchor_date, user_pseudo_id,
    COUNT(DISTINCT IF(event_date >= DATE_SUB(anchor_date, INTERVAL 7  DAY), ga_session_id, NULL)) AS visits_7d,
    COUNT(DISTINCT IF(event_date >= DATE_SUB(anchor_date, INTERVAL 14 DAY), ga_session_id, NULL)) AS visits_14d,
    COUNT(DISTINCT ga_session_id) AS visits_30d,
    COUNTIF(event_name = 'page_view') AS page_views_30d,
    MAX(event_date) AS last_visit_date
  FROM events_with_pages
  GROUP BY anchor_date, user_pseudo_id
),

-- 8) Visite a content page (itinerari/destinazioni) + quote + FYC + lead per tipo + guests-info
content_page_visits AS (
  SELECT
    anchor_date, user_pseudo_id,
    COUNTIF(is_itinerary_page)   AS itinerary_page_visits_30d,
    COUNTIF(is_destination_page) AS destination_page_visits_30d,
    COUNTIF(is_quote_page)       AS quote_page_visits_30d,
    COUNTIF(is_fyc_filter)       AS filtri_fyc_30d,
    COUNTIF(event_name = 'generate_lead_RAB')  AS lead_rab_30d,
    COUNTIF(event_name = 'generate_lead_RAQ')  AS lead_raq_30d,
    COUNTIF(event_name = 'generate_lead_SFO')  AS lead_sfo_30d,
    COUNTIF(event_name = 'generate_lead_WEBQ') AS lead_webq_30d,
    MAX(IF(is_guests_info, 1, 0)) AS has_seen_guests_info_30d
  FROM events_with_pages
  GROUP BY anchor_date, user_pseudo_id
),

-- 9) Engagement ripetuto: max visite sullo STESSO itinerario / destinazione
max_same_itinerary AS (
  SELECT anchor_date, user_pseudo_id, MAX(cnt) AS max_same_itinerary_30d
  FROM (
    SELECT anchor_date, user_pseudo_id, itinerary_id, COUNT(*) AS cnt
    FROM events_with_pages WHERE itinerary_id IS NOT NULL
    GROUP BY anchor_date, user_pseudo_id, itinerary_id
  ) GROUP BY anchor_date, user_pseudo_id
),
max_same_destination AS (
  SELECT anchor_date, user_pseudo_id, MAX(cnt) AS max_same_destination_30d
  FROM (
    SELECT anchor_date, user_pseudo_id, destination_id, COUNT(*) AS cnt
    FROM events_with_pages WHERE destination_id IS NOT NULL
    GROUP BY anchor_date, user_pseudo_id, destination_id
  ) GROUP BY anchor_date, user_pseudo_id
),

-- 10) Itinerario / destinazione piu' visti (per la segmentazione)
most_viewed_itinerary AS (
  SELECT anchor_date, user_pseudo_id, itinerary_id AS most_viewed_itinerary
  FROM (
    SELECT anchor_date, user_pseudo_id, itinerary_id, COUNT(*) AS cnt,
           ROW_NUMBER() OVER (PARTITION BY anchor_date, user_pseudo_id ORDER BY COUNT(*) DESC) AS rn
    FROM events_with_pages WHERE itinerary_id IS NOT NULL
    GROUP BY anchor_date, user_pseudo_id, itinerary_id
  ) WHERE rn = 1
),
most_viewed_destination AS (
  SELECT anchor_date, user_pseudo_id, destination_id AS most_viewed_destination
  FROM (
    SELECT anchor_date, user_pseudo_id, destination_id, COUNT(*) AS cnt,
           ROW_NUMBER() OVER (PARTITION BY anchor_date, user_pseudo_id ORDER BY COUNT(*) DESC) AS rn
    FROM events_with_pages WHERE destination_id IS NOT NULL
    GROUP BY anchor_date, user_pseudo_id, destination_id
  ) WHERE rn = 1
),

-- 11) Diversita' di interesse (multi itinerario / destinazione)
diversity_features AS (
  SELECT
    anchor_date, user_pseudo_id,
    IF(COUNT(DISTINCT itinerary_id)   > 1, 1, 0) AS multi_itinerary_interest,
    IF(COUNT(DISTINCT destination_id) > 1, 1, 0) AS multi_destination_interest
  FROM events_with_pages
  GROUP BY anchor_date, user_pseudo_id
),

-- 12) Target: conversione nei 14 gg SUCCESSIVI (generate_lead_WBOF_01)
target_labels AS (
  SELECT DISTINCT a.anchor_date, e.user_pseudo_id, 1 AS target_conversion
  FROM `silversea-293815.analytics_256550454.events_*` e
  CROSS JOIN anchor_dates a
  WHERE _TABLE_SUFFIX BETWEEN '20250302' AND '20250513'
    AND e.event_name = 'generate_lead_WBOF_01'   -- target v3 (solo WBOF_01)
    AND e.user_pseudo_id IS NOT NULL
    AND PARSE_DATE('%Y%m%d', e.event_date)
        BETWEEN a.anchor_date AND DATE_ADD(a.anchor_date, INTERVAL 14 DAY)
),

-- 13) Assemblaggio feature + derivate V2
pre_output AS (
  SELECT
    au.anchor_date,
    au.user_pseudo_id,
    COALESCE(tl.target_conversion, 0) AS target_conversion,

    -- provenienza
    COALESCE(vs.visits_vs_count, 0)    AS visits_vs_count,
    COALESCE(vs.visits_no_vs_count, 0) AS visits_no_vs_count,

    -- navigazione
    COALESCE(vf.visits_7d, 0)  AS visits_7d,
    COALESCE(vf.visits_14d, 0) AS visits_14d,
    COALESCE(vf.visits_30d, 0) AS visits_30d,

    -- content / engagement / lead
    COALESCE(cp.itinerary_page_visits_30d, 0)   AS itinerary_page_visits_30d,
    COALESCE(cp.destination_page_visits_30d, 0) AS destination_page_visits_30d,
    COALESCE(msi.max_same_itinerary_30d, 0)     AS max_same_itinerary_30d,
    COALESCE(msd.max_same_destination_30d, 0)   AS max_same_destination_30d,
    COALESCE(cp.filtri_fyc_30d, 0)              AS filtri_fyc_30d,
    COALESCE(cp.lead_rab_30d, 0)                AS lead_rab_30d,
    COALESCE(cp.lead_raq_30d, 0)                AS lead_raq_30d,
    COALESCE(cp.lead_sfo_30d, 0)                AS lead_sfo_30d,
    COALESCE(cp.lead_webq_30d, 0)               AS lead_webq_30d,
    COALESCE(cp.quote_page_visits_30d, 0)       AS quote_page_visits_30d,

    -- geo
    mf.market,

    -- dimensioni descrittive (segmentazione)
    mvi.most_viewed_itinerary,
    mvd.most_viewed_destination,

    -- V2 derivate
    DATE_DIFF(au.anchor_date, vf.last_visit_date, DAY) AS days_since_last_visit,
    SAFE_DIVIDE(vf.visits_7d, vf.visits_30d)           AS visits_trend,          -- << definizione: quota visite recenti
    SAFE_DIVIDE(vf.page_views_30d, vf.visits_30d)      AS avg_pages_per_visit,
    IF(COALESCE(cp.lead_rab_30d,0)+COALESCE(cp.lead_raq_30d,0)
       +COALESCE(cp.lead_sfo_30d,0)+COALESCE(cp.lead_webq_30d,0) > 0, 1, 0) AS has_lead_any,
    SAFE_DIVIDE(cp.quote_page_visits_30d, vf.visits_30d) AS quote_to_visit_ratio,
    COALESCE(div.multi_itinerary_interest, 0)   AS multi_itinerary_interest,
    COALESCE(div.multi_destination_interest, 0) AS multi_destination_interest,

    -- V3
    COALESCE(cp.has_seen_guests_info_30d, 0)    AS has_seen_guests_info_30d

  FROM active_users_per_anchor au
  LEFT JOIN vs_flags vs                ON au.anchor_date = vs.anchor_date  AND au.user_pseudo_id = vs.user_pseudo_id
  LEFT JOIN market_feature mf          ON au.anchor_date = mf.anchor_date  AND au.user_pseudo_id = mf.user_pseudo_id
  LEFT JOIN visits_features vf         ON au.anchor_date = vf.anchor_date  AND au.user_pseudo_id = vf.user_pseudo_id
  LEFT JOIN content_page_visits cp     ON au.anchor_date = cp.anchor_date  AND au.user_pseudo_id = cp.user_pseudo_id
  LEFT JOIN max_same_itinerary msi     ON au.anchor_date = msi.anchor_date AND au.user_pseudo_id = msi.user_pseudo_id
  LEFT JOIN max_same_destination msd   ON au.anchor_date = msd.anchor_date AND au.user_pseudo_id = msd.user_pseudo_id
  LEFT JOIN most_viewed_itinerary mvi  ON au.anchor_date = mvi.anchor_date AND au.user_pseudo_id = mvi.user_pseudo_id
  LEFT JOIN most_viewed_destination mvd ON au.anchor_date = mvd.anchor_date AND au.user_pseudo_id = mvd.user_pseudo_id
  LEFT JOIN diversity_features div      ON au.anchor_date = div.anchor_date AND au.user_pseudo_id = div.user_pseudo_id
  LEFT JOIN target_labels tl            ON au.anchor_date = tl.anchor_date  AND au.user_pseudo_id = tl.user_pseudo_id
)

-- OUTPUT FINALE
SELECT *
FROM pre_output
WHERE visits_30d > 0
ORDER BY user_pseudo_id, anchor_date;
