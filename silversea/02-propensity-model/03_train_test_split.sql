-- =============================================================================
-- SILVERSEA PROPENSITY — TRAIN/TEST SPLIT (80/20 PER UTENTE)  [script verbatim]
-- =============================================================================
-- Split a livello UTENTE (non per riga) per evitare data leakage: tutte le righe
-- di uno stesso utente finiscono o in train o in test.
--   dataset_split = FALSE -> train (80%)
--   dataset_split = TRUE  -> test  (20%)
-- =============================================================================

CREATE OR REPLACE TABLE `dm-2021-hdm-01.Silversea_Playground.propensity_split_full_v3` AS

WITH
-- Assegna ogni UTENTE a train/test (80/20)
user_split AS (
  SELECT
    user_pseudo_id,
    CASE
      WHEN RAND() < 0.8 THEN FALSE  -- 80% train
      ELSE TRUE                      -- 20% test
    END AS dataset_split
  FROM (
    SELECT DISTINCT user_pseudo_id
    FROM `dm-2021-hdm-01.Silversea_Playground.propensity_training_v3`
  )
)

-- Applica lo split a tutte le righe dell'utente
SELECT
  t.*,
  u.dataset_split
FROM `dm-2021-hdm-01.Silversea_Playground.propensity_training_v3` t
JOIN user_split u ON t.user_pseudo_id = u.user_pseudo_id;
