-- =============================================================================
-- UTILITY — RIMUOVERE GLI UTENTI ESPOSTI A PIU' DI UNA VARIANTE
-- =============================================================================
-- Requisito cliente: ogni individuo deve essere stato esposto al MASSIMO a una variante.
-- Pattern riusabile: identifica gli user_pseudo_id "contaminati" (piu' di un variation_id
-- distinto) e li esclude dal resto dell'estrazione con NOT EXISTS (NON NOT IN: fallisce
-- con i NULL).
--
-- Sostituire <EXPERIMENT_ID> e il periodo. Adattabile a EJ e Silversea.
-- =============================================================================

WITH

-- Utenti esposti a piu' di una variante
users_multi_variation AS (
  SELECT user_pseudo_id
  FROM `ejattribution.analytics_268301381.events_*`
  WHERE _TABLE_SUFFIX BETWEEN 'AAAAMMGG' AND 'AAAAMMGG'   -- << IMPOSTA PERIODO
    AND event_name = 'experiment_viewed'
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'experiment_id') = '<EXPERIMENT_ID>'
    AND user_pseudo_id IS NOT NULL
  GROUP BY user_pseudo_id
  HAVING COUNT(DISTINCT
    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'variation_id')
  ) > 1
),

-- Estrazione pulita (qui: assegnazione utente-variante mono-variante)
clean_extraction AS (
  SELECT DISTINCT
    e.user_pseudo_id,
    (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'variation_id') AS variation_id
  FROM `ejattribution.analytics_268301381.events_*` e
  WHERE _TABLE_SUFFIX BETWEEN 'AAAAMMGG' AND 'AAAAMMGG'
    AND e.event_name = 'experiment_viewed'
    AND (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'experiment_id') = '<EXPERIMENT_ID>'
    AND e.user_pseudo_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM users_multi_variation umv WHERE umv.user_pseudo_id = e.user_pseudo_id
    )
)

SELECT variation_id, COUNT(DISTINCT user_pseudo_id) AS utenti
FROM clean_extraction
GROUP BY variation_id
ORDER BY variation_id;
