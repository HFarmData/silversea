-- =============================================================================
-- SILVERSEA PROPENSITY — CREATE MODEL v3  [script verbatim]
-- =============================================================================
-- BOOSTED_TREE_CLASSIFIER (XGBoost). Split CUSTOM via colonna dataset_split.
-- NOTA (Problema 2): in questo CREATE MODEL la feature `market` NON e' inclusa,
-- mentre compare nello scoring/predictions -> il modello la ignora. Per usarla
-- davvero, aggiungerla qui e riallenare. Lasciato verbatim per fedelta'.
-- =============================================================================

CREATE OR REPLACE MODEL `dm-2021-hdm-01.Silversea_Playground.propensity_model_v3`
OPTIONS(
  model_type = 'BOOSTED_TREE_CLASSIFIER',
  input_label_cols = ['target_conversion'],
  data_split_col = 'dataset_split',
  data_split_method = 'CUSTOM',

  num_parallel_tree = 1,
  max_iterations = 100,
  learn_rate = 0.1,
  max_tree_depth = 6,
  min_tree_child_weight = 1,
  subsample = 0.8,
  colsample_bytree = 0.8,

  early_stop = TRUE,
  min_rel_progress = 0.001,

  auto_class_weights = TRUE,

  l1_reg = 0.1,
  l2_reg = 1.0

) AS

SELECT
  target_conversion,

  -- Feature originali
  visits_vs_count,
  visits_no_vs_count,
  visits_7d,
  visits_14d,
  visits_30d,
  itinerary_page_visits_30d,
  destination_page_visits_30d,
  max_same_itinerary_30d,
  max_same_destination_30d,
  filtri_fyc_30d,
  lead_rab_30d,
  lead_raq_30d,
  lead_sfo_30d,
  lead_webq_30d,
  quote_page_visits_30d,

  -- Feature V2
  days_since_last_visit,
  visits_trend,
  avg_pages_per_visit,
  has_lead_any,
  quote_to_visit_ratio,
  multi_itinerary_interest,
  multi_destination_interest,

  -- NUOVA Feature V3
  has_seen_guests_info_30d,

  dataset_split

FROM `dm-2021-hdm-01.Silversea_Playground.propensity_split_full_v3`;
