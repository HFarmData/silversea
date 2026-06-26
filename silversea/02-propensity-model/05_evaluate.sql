-- =============================================================================
-- SILVERSEA PROPENSITY — EVALUATE & LIFT  [script verbatim]
-- =============================================================================
-- (A) Metriche generali sul TEST SET (split_full_v3, dataset_split = TRUE)
-- (B) Metriche sul dataset di SCORING (apr 2025) come proxy out-of-time
-- (C) Lift per fascia di propensity
-- NOTA: nel blocco (A) la lista feature include `market` (26), nel blocco (B) no (25):
--       riflette l'incoerenza market train/scoring (Problema 2). Lasciato verbatim.
-- =============================================================================


-- (A) Metriche generali sul TEST SET ------------------------------------------
SELECT
  'Model V2 Full' AS model_name,
  *
FROM ML.EVALUATE(
  MODEL `dm-2021-hdm-01.Silversea_Playground.propensity_model_v3`,
  (
    SELECT
      target_conversion,
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
      market,
      days_since_last_visit,
      visits_trend,
      avg_pages_per_visit,
      has_lead_any,
      quote_to_visit_ratio,
      multi_itinerary_interest,
      multi_destination_interest,
      has_seen_guests_info_30d
    FROM `dm-2021-hdm-01.Silversea_Playground.propensity_split_full_v3`
    WHERE dataset_split = TRUE
  )
);


-- (B) Metriche sul dataset di SCORING (apr 2025) ------------------------------
SELECT *
FROM ML.EVALUATE(
  MODEL `dm-2021-hdm-01.Silversea_Playground.propensity_model_v3`,
  (
    SELECT
      target_conversion,
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
      days_since_last_visit,
      visits_trend,
      avg_pages_per_visit,
      has_lead_any,
      quote_to_visit_ratio,
      multi_itinerary_interest,
      multi_destination_interest,
      has_seen_guests_info_30d
    FROM `dm-2021-hdm-01.Silversea_Playground.propensity_scoring_apr_2025_v3`
  )
);


-- (C) Lift per fascia di propensity -------------------------------------------
-- NB: questo blocco (come fornito) valuta il modello v1 full sul relativo split.
--     Aggiornare MODEL/tabella a *_v3 se si vuole il lift sulla v3.
WITH predictions AS (
  SELECT
    target_conversion AS actual,
    (SELECT prob FROM UNNEST(predicted_target_conversion_probs) WHERE label = 1) AS propensity_score
  FROM ML.PREDICT(
    MODEL `dm-2021-hdm-01.Silversea_Playground.propensity_model_v1_full`,
    (
      SELECT *
      FROM `dm-2021-hdm-01.Silversea_Playground.propensity_split_full`
      WHERE dataset_split = TRUE
    )
  )
),

overall_rate AS (
  SELECT SUM(actual) / COUNT(*) AS baseline_rate
  FROM predictions
),

with_bands AS (
  SELECT
    *,
    CASE
      WHEN propensity_score >= 0.7 THEN '1. Alta'
      WHEN propensity_score >= 0.4 THEN '2. Medio-Alta'
      WHEN propensity_score >= 0.2 THEN '3. Media'
      WHEN propensity_score >= 0.1 THEN '4. Medio-Bassa'
      ELSE '5. Bassa'
    END AS propensity_band
  FROM predictions
)

SELECT
  propensity_band,
  COUNT(*) AS users,
  SUM(actual) AS conversions,
  ROUND(SUM(actual) / COUNT(*) * 100, 3) AS conversion_rate_pct,
  ROUND((SUM(actual) / COUNT(*)) / (SELECT baseline_rate FROM overall_rate), 1) AS lift_vs_average
FROM with_bands
GROUP BY propensity_band
ORDER BY propensity_band;
