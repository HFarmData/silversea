-- =============================================================================
-- EJ — PAGE PATH A RITROSO PRIMA DELLA CONVERSIONE (pivot per posizione sessione)
-- =============================================================================
-- Per ogni conversione, ricostruisce le pagine viste nelle X sessioni che la
-- precedono + nella sessione di conversione (troncata prima dell'evento).
--
-- INDICIZZAZIONE A RITROSO:
--   session_minus_0  = sessione di conversione (solo page_view PRIMA dell'azione)
--   session_minus_1  = sessione immediatamente precedente
--   ...              = sessioni progressivamente piu' lontane
--   session_minus_X  = X-esima sessione precedente
--
-- PROFONDITA' X: 7 per Booking Hold, 10 per Purchase.
-- -> Lanciare UNA VOLTA PER CASISTICA:
--      * impostare il filtro action_type (vedi STEP 1)
--      * impostare la soglia QUALIFY (STEP 3): 7 per BH, 10 per Purchase
--    Le colonne session_minus_8..10 restano vuote nel run BH.
--
-- LOGICA DI RESET coerente con le altre query (LAG -> prev_action_ts).
-- DISTINCT: una pagina vista N volte nella stessa sessione conta 1.
-- =============================================================================

WITH

-- STEP 1: occorrenze di conversione (cattura anche la sessione di conversione)
-- >> Per il run "Booking Hold": tenere solo il ramo BH (commentare Purchase)
-- >> Per il run "Purchase":     tenere solo il ramo Purchase (commentare BH)
raw_actions AS (
  SELECT
    user_pseudo_id,
    event_timestamp AS action_ts,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS conversion_session_id
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX >= 'AAAAMMGG'   -- << IMPOSTA PERIODO AZIONI
    AND (
      -- Booking Hold
      (event_name = 'generate_lead'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'lead_name') = 'booking')
      -- Purchase (commentare il ramo non in uso)
      OR
      (event_name = 'purchase'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_journey_is_destex') != 'YES'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'payment_type') != 'total')
    )
),

-- STEP 2: timestamp della conversione precedente (reset)
actions_with_prev AS (
  SELECT
    user_pseudo_id,
    action_ts,
    conversion_session_id,
    LAG(action_ts) OVER (PARTITION BY user_pseudo_id ORDER BY action_ts) AS prev_action_ts
  FROM raw_actions
),

-- STEP 3: tutte le sessioni dell'utente (storico completo)
user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    MIN(event_timestamp) AS session_start_ts
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
  GROUP BY user_pseudo_id, session_id
),

-- STEP 4a: sessioni PRECEDENTI numerate a ritroso (-1 piu' recente)
ranked_prev_sessions AS (
  SELECT
    a.user_pseudo_id,
    a.action_ts,
    s.session_id,
    -ROW_NUMBER() OVER (
      PARTITION BY a.user_pseudo_id, a.action_ts
      ORDER BY s.session_start_ts DESC
    ) AS session_position
  FROM actions_with_prev a
  JOIN user_sessions s
    ON a.user_pseudo_id = s.user_pseudo_id
   AND s.session_start_ts < a.action_ts
   AND s.session_id != a.conversion_session_id
   AND (a.prev_action_ts IS NULL OR s.session_start_ts > a.prev_action_ts)
  QUALIFY ROW_NUMBER() OVER (
      PARTITION BY a.user_pseudo_id, a.action_ts
      ORDER BY s.session_start_ts DESC
    ) <= 10   -- << PROFONDITA' X: 7 per Booking Hold, 10 per Purchase
),

-- STEP 4b: sessione di CONVERSIONE -> posizione 0
conversion_session AS (
  SELECT user_pseudo_id, action_ts, conversion_session_id AS session_id, 0 AS session_position
  FROM actions_with_prev
),

all_sessions AS (
  SELECT * FROM ranked_prev_sessions
  UNION ALL
  SELECT * FROM conversion_session
),

-- STEP 5: page_view (buffer ampio per coprire sessioni vecchie della coda lunga)
page_views AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_url
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20251001' AND '20260428'   -- << BUFFER PAGE_VIEW (allargare se serve)
    AND event_name = 'page_view'
),

-- STEP 6: pagine per sessione (DISTINCT) con troncamento della sessione 0
session_pages AS (
  SELECT DISTINCT
    t.user_pseudo_id,
    t.action_ts,
    t.session_position,
    p.page_url
  FROM all_sessions t
  JOIN page_views p
    ON p.user_pseudo_id = t.user_pseudo_id
   AND p.session_id = t.session_id
   AND (t.session_position != 0 OR p.event_timestamp < t.action_ts)
  WHERE p.page_url IS NOT NULL
)

-- OUTPUT: pivot. Ogni cella = numero di "session-instances" in cui l'URL e'
-- apparso in quella posizione, sommando su tutte le conversioni di tutti gli utenti.
SELECT
  page_url,
  COUNTIF(session_position = 0)   AS session_minus_0,
  COUNTIF(session_position = -1)  AS session_minus_1,
  COUNTIF(session_position = -2)  AS session_minus_2,
  COUNTIF(session_position = -3)  AS session_minus_3,
  COUNTIF(session_position = -4)  AS session_minus_4,
  COUNTIF(session_position = -5)  AS session_minus_5,
  COUNTIF(session_position = -6)  AS session_minus_6,
  COUNTIF(session_position = -7)  AS session_minus_7,
  COUNTIF(session_position = -8)  AS session_minus_8,
  COUNTIF(session_position = -9)  AS session_minus_9,
  COUNTIF(session_position = -10) AS session_minus_10,
  COUNT(*) AS total_appearances
FROM session_pages
GROUP BY page_url
ORDER BY total_appearances DESC;
