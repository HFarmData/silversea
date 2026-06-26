-- =============================================================================
-- EJ — GIORNI PRIMA DI BOOKING HOLD / PURCHASE
-- =============================================================================
-- Per ogni occorrenza di conversione, giorni trascorsi dall'inizio della finestra
-- di reset (prima sessione dopo la conversione precedente, o prima visita assoluta
-- se non ci sono conversioni precedenti) fino all'azione.
-- LOGICA DI RESET coerente con 01_sessions_before.sql.
--
-- Output: media, mediana e distribuzione a fasce, per casistica (BH, Purchase, Any).
-- NOTA: la distribuzione e' fortemente skewed (mediana 0-3, media >10). Usare la mediana.
-- =============================================================================

WITH

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
  WHERE _TABLE_SUFFIX >= 'AAAAMMGG'   -- << IMPOSTA PERIODO AZIONI
    AND (
      (event_name = 'generate_lead'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'lead_name') = 'booking')
      OR
      (event_name = 'purchase'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'p_journey_is_destex') != 'YES'
       AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'payment_type') != 'total')
    )
),

all_actions AS (
  SELECT user_pseudo_id, event_timestamp, action_type FROM raw_actions
  UNION ALL
  SELECT user_pseudo_id, event_timestamp, 'Any (OR)' AS action_type FROM raw_actions
),

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

user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    MIN(event_timestamp) AS session_start_ts
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
  GROUP BY user_pseudo_id, session_id
),

-- Inizio finestra di reset = prima sessione nella finestra (prev_action_ts, action_ts]
window_start AS (
  SELECT
    a.user_pseudo_id,
    a.action_type,
    a.action_ts,
    MIN(s.session_start_ts) AS window_start_ts
  FROM actions_with_prev a
  JOIN user_sessions s
    ON a.user_pseudo_id = s.user_pseudo_id
   AND s.session_start_ts <= a.action_ts
   AND (a.prev_action_ts IS NULL OR s.session_start_ts > a.prev_action_ts)
  GROUP BY a.user_pseudo_id, a.action_type, a.action_ts
),

with_days AS (
  SELECT
    action_type,
    TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(action_ts),
      TIMESTAMP_MICROS(window_start_ts),
      DAY) AS days
  FROM window_start
)

-- OUTPUT: media + mediana e distribuzione a fasce in un'unica tabella
-- PARTE A: summary
SELECT
  action_type,
  'summary' AS row_type,
  NULL AS days_bucket,
  COUNT(*) AS occurrences,
  ROUND(AVG(days), 2) AS avg_days,
  APPROX_QUANTILES(days, 100)[OFFSET(50)] AS median_days
FROM with_days
GROUP BY action_type

UNION ALL

-- PARTE B: distribuzione a fasce (prefisso numerico per ordinamento)
SELECT
  action_type,
  'distribution' AS row_type,
  CASE
    WHEN days <= 0 THEN '0 - Same day'
    WHEN days BETWEEN 1 AND 3 THEN '1 - 1-3 days'
    WHEN days BETWEEN 4 AND 7 THEN '2 - 4-7 days'
    WHEN days BETWEEN 8 AND 14 THEN '3 - 8-14 days'
    WHEN days BETWEEN 15 AND 30 THEN '4 - 15-30 days'
    WHEN days BETWEEN 31 AND 90 THEN '5 - 31-90 days'
    ELSE '6 - 90+ days'
  END AS days_bucket,
  COUNT(*) AS occurrences,
  NULL AS avg_days,
  NULL AS median_days
FROM with_days
GROUP BY action_type, days_bucket

ORDER BY action_type, row_type, days_bucket;


-- =============================================================================
-- VARIANTE STORICA (v1, NO reset): giorni dalla PRIMA visita assoluta alla PRIMA
-- azione per tipo. Sostituita dalla versione con reset qui sopra. Conservata per
-- riferimento / confronto.
-- =============================================================================
-- WITH first_action AS (
--   SELECT user_pseudo_id, action_type, MIN(event_timestamp) AS first_action_ts
--   FROM all_actions GROUP BY user_pseudo_id, action_type
-- ),
-- first_visit AS (
--   SELECT user_pseudo_id, MIN(event_timestamp) AS first_visit_ts
--   FROM `ejattribution.analytics_268301381.events_*` GROUP BY user_pseudo_id
-- )
-- SELECT a.action_type, COUNT(*) AS users,
--   ROUND(AVG(TIMESTAMP_DIFF(TIMESTAMP_MICROS(a.first_action_ts), TIMESTAMP_MICROS(f.first_visit_ts), DAY)),2) AS avg_days,
--   APPROX_QUANTILES(TIMESTAMP_DIFF(TIMESTAMP_MICROS(a.first_action_ts), TIMESTAMP_MICROS(f.first_visit_ts), DAY),100)[OFFSET(50)] AS median_days
-- FROM first_action a JOIN first_visit f USING (user_pseudo_id)
-- GROUP BY a.action_type ORDER BY a.action_type;
