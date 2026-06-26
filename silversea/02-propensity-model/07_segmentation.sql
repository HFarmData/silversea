-- =============================================================================
-- SILVERSEA PROPENSITY — SEGMENTAZIONE per fascia + flag  [script verbatim]
-- =============================================================================
-- Crosstab: utenti distinti per fascia di propensity (Alta/Media/Bassa), market,
-- destinazione/itinerario piu' visti e una serie di flag Si'/No comportamentali.
-- =============================================================================

WITH tp AS (
  SELECT
    user_pseudo_id,
    market,
    most_viewed_destination,
    most_viewed_itinerary,

    -- flag quote page visit
    CASE
      WHEN quote_page_visits_30d > 0 THEN 'Sì'
      ELSE 'No'
    END AS flag_quote_30d,

    -- flag lead per tipologia
    CASE
      WHEN lead_rab_30d > 0 THEN 'Sì'
      ELSE 'No'
    END AS flag_lead_rab_30d,

    CASE
      WHEN lead_raq_30d > 0 THEN 'Sì'
      ELSE 'No'
    END AS flag_lead_raq_30d,

    CASE
      WHEN lead_sfo_30d > 0 THEN 'Sì'
      ELSE 'No'
    END AS flag_lead_sfo_30d,

    CASE
      WHEN lead_webq_30d > 0 THEN 'Sì'
      ELSE 'No'
    END AS flag_lead_webq_30d,

    CASE
      WHEN visits_vs_count > 0 THEN 'Sì'
      ELSE 'No'
    END AS flag_visits_vs_count,

    CASE
      WHEN visits_no_vs_count > 0 THEN 'Sì'
      ELSE 'No'
    END AS flag_visits_no_vs_count,

    CASE
      WHEN propensity_score > 0.8 THEN 'Alta'
      WHEN propensity_score >= 0.4 AND propensity_score <= 0.8 THEN 'Media'
      WHEN propensity_score > 0 AND propensity_score < 0.4 THEN 'Bassa'
    END AS Propensity,

    CASE
      WHEN has_seen_guests_info_30d > 0 THEN 'Sì'
      ELSE 'No'
    END AS has_seen_guests_info_30d,

  FROM `dm-2021-hdm-01.Silversea_Playground.propensity_predictions_apr_2025_v3`
)

SELECT
  Propensity,
  market,
  most_viewed_destination,
  most_viewed_itinerary,
  flag_quote_30d,
  flag_lead_rab_30d,
  flag_lead_raq_30d,
  flag_lead_sfo_30d,
  flag_lead_webq_30d,
  flag_visits_vs_count,
  flag_visits_no_vs_count,
  has_seen_guests_info_30d,
  COUNT(DISTINCT user_pseudo_id) AS cnt
FROM tp
GROUP BY
  1,2,3,4,5,6,7,8,9,10,11,12
ORDER BY cnt DESC;
