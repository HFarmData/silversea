-- =============================================================================
-- SILVERSEA PROPENSITY — PREDICTIONS (scoring apr 2025)  [script verbatim]
-- =============================================================================
-- Applica il modello v3 al dataset di scoring e materializza la tabella con
-- propensity_score = probabilita' della classe label=1.
-- =============================================================================

CREATE OR REPLACE TABLE `dm-2021-hdm-01.Silversea_Playground.propensity_predictions_apr_2025_v3` AS

SELECT
  t.*,
  (SELECT prob FROM UNNEST(p.predicted_target_conversion_probs) WHERE label = 1) AS propensity_score
FROM ML.PREDICT(
  MODEL `dm-2021-hdm-01.Silversea_Playground.propensity_model_v3`,
  (
    SELECT
      user_pseudo_id,
      anchor_date,
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
    FROM `dm-2021-hdm-01.Silversea_Playground.propensity_scoring_apr_2025_v3`
  )
) p
JOIN `dm-2021-hdm-01.Silversea_Playground.propensity_scoring_apr_2025_v3` t
  ON p.user_pseudo_id = t.user_pseudo_id
  AND p.anchor_date = t.anchor_date;
