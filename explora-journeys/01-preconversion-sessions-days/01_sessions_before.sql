-- =============================================================================
-- EJ — NUMERO DI SESSIONI PRIMA DI BOOKING HOLD / PURCHASE
-- =============================================================================
-- Per ogni occorrenza di Booking Hold o Purchase, conta quante sessioni l'utente
-- ha fatto prima di quell'azione.
-- LOGICA DI RESET: se lo stesso utente converte piu' volte, il conteggio riparte
-- dopo ogni conversione (le sessioni della 2a conversione partono dalla sessione
-- successiva alla 1a). Implementato con LAG() per ottenere prev_action_ts.
--
-- Output: 3 righe -> Booking Hold, Purchase, Any (OR).
-- Periodo azioni: placeholder (originale: dal 2026 in poi). Sessioni: tutto lo storico.
-- =============================================================================

WITH

-- STEP 1: tutte le occorrenze delle due conversioni nel periodo azioni
raw_actions AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    CASE
      WHEN event_name = 'generate_lead'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'lead_name') = 'booking'
      THEN 'Booking Hold'
      WHEN event_name = 'purchase'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_journey_is_destex') != 'YES'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'payment_type') != 'total'
      THEN 'Purchase'
    END AS action_type
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX >= 'AAAAMMGG'   -- << IMPOSTA PERIODO AZIONI (es. '20260101')
    AND (
      (event_name = 'generate_lead'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'lead_name') = 'booking')
      OR
      (event_name = 'purchase'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_journey_is_destex') != 'YES'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'payment_type') != 'total')
    )
),

-- STEP 2: replichiamo le azioni anche come casistica "Any (OR)" (tipo unico)
all_actions AS (
  SELECT user_pseudo_id, event_timestamp, action_type FROM raw_actions
  UNION ALL
  SELECT user_pseudo_id, event_timestamp, 'Any (OR)' AS action_type FROM raw_actions
),

-- STEP 3: per ogni azione, timestamp dell'azione PRECEDENTE dello stesso tipo (reset)
actions_with_prev AS (
  SELECT
    user_pseudo_id,
    action_type,
    event_timestamp AS action_ts,
    LAG(event_timestamp) OVER (
      PARTITION BY user_pseudo_id, action_type
      ORDER BY event_timestamp
    ) AS prev_action_ts
  FROM all_actions
),

-- STEP 4: tutte le sessioni dell'utente (su tutto lo storico)
user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    MIN(event_timestamp) AS session_start_ts
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
  GROUP BY user_pseudo_id, session_id
),

-- STEP 5: conta le sessioni nella finestra di reset
-- finestra = (prev_action_ts, action_ts]  (esclusa la precedente conversione, inclusa l'azione)
sessions_before AS (
  SELECT
    a.user_pseudo_id,
    a.action_type,
    a.action_ts,
    COUNT(DISTINCT s.session_id) AS sessions_before_action
  FROM actions_with_prev a
  JOIN user_sessions s
    ON a.user_pseudo_id = s.user_pseudo_id
   AND s.session_start_ts <= a.action_ts
   AND (a.prev_action_ts IS NULL OR s.session_start_ts > a.prev_action_ts)
  GROUP BY a.user_pseudo_id, a.action_type, a.action_ts
)

-- OUTPUT: media, mediana e numero di occorrenze per casistica
SELECT
  action_type,
  COUNT(*) AS occurrences,
  ROUND(AVG(sessions_before_action), 2) AS avg_sessions_before,
  APPROX_QUANTILES(sessions_before_action, 100)[OFFSET(50)] AS median_sessions_before
FROM sessions_before
GROUP BY action_type
ORDER BY action_type;


-- =============================================================================
-- QUERY DI SUPPORTO: distribuzione a fasce del numero di sessioni
-- (incollare al posto del SELECT finale, riusando le CTE sopra)
-- =============================================================================
-- SELECT
--   action_type,
--   CASE
--     WHEN sessions_before_action = 0 THEN '0 (same session)'
--     WHEN sessions_before_action = 1 THEN '1'
--     WHEN sessions_before_action BETWEEN 2 AND 3  THEN '2-3'
--     WHEN sessions_before_action BETWEEN 4 AND 7  THEN '4-7'
--     WHEN sessions_before_action BETWEEN 8 AND 14 THEN '8-14'
--     WHEN sessions_before_action BETWEEN 15 AND 30 THEN '15-30'
--     WHEN sessions_before_action BETWEEN 31 AND 90 THEN '31-90'
--     ELSE '91+'
--   END AS sessions_bucket,
--   COUNT(*) AS occurrences
-- FROM sessions_before
-- GROUP BY action_type, sessions_bucket
-- ORDER BY action_type, MIN(sessions_before_action);
