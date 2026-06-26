-- =============================================================================
-- SILVERSEA — FUNNEL WEBQ: visitatori, WEBQ, conversione booking, tempo medio
-- =============================================================================
-- Per ciascuno step (guests / category / fare): visitatori dello step, utenti che
-- hanno lasciato una WEBQ, numero di WEBQ, quanti hanno convertito in booking CRM
-- (dopo la WEBQ) e tempo medio WEBQ -> ConfirmationDate.
--
-- Conversione = booking CRM con BkgStatus='BK' e ConfirmationDate > data WEBQ.
-- Catena: user_pseudo_id -> super_id.google_ids -> super_id_latest_individual_id
--         -> Azure_CRM_BkgRole -> Azure_CRM_BkgHdr.
-- NB: copertura super_id limitata (vedi crm_linking_attempts.sql).
-- =============================================================================

WITH

-- 1) WEBQ per step
webq_events AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    PARSE_DATE('%Y%m%d', event_date) AS webq_date,
    (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'voyage_funnel_step_name') AS funnel_step
  FROM `silversea-293815.analytics_256550454.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20251203' AND '20260228'   -- << IMPOSTA PERIODO
    AND event_name = 'generate_lead_WEBQ'
    AND user_pseudo_id IS NOT NULL
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'voyage_funnel_step_name')
        IN ('guests WEBQ', 'category WEBQ', 'fare WEBQ')
),

-- 2) Visitatori dello step (denominatore): page_view sullo step corrispondente
step_visitors AS (
  SELECT
    CASE (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'voyage_funnel_step_name')
      WHEN 'guests'   THEN 'guests WEBQ'
      WHEN 'category' THEN 'category WEBQ'
      WHEN 'fare'     THEN 'fare WEBQ'
    END AS funnel_step,
    COUNT(DISTINCT user_pseudo_id) AS visitors
  FROM `silversea-293815.analytics_256550454.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20251203' AND '20260228'
    AND event_name = 'page_view'
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'voyage_funnel_step_name')
        IN ('guests', 'category', 'fare')
    AND user_pseudo_id IS NOT NULL
  GROUP BY funnel_step
),

-- 3) user_pseudo_id -> super_id (google_ids e' un array)
with_super_id AS (
  SELECT w.*, s.super_id
  FROM webq_events w
  JOIN `silversea-293815.data_landing_clean.super_id` s
    ON w.user_pseudo_id IN UNNEST(s.google_ids)
),

-- 4) super_id -> IndividualId
with_individual AS (
  SELECT w.*, CAST(i.latest_individual_id AS STRING) AS IndividualId
  FROM with_super_id w
  JOIN `silversea-293815.data_landing_clean.super_id_latest_individual_id` i
    ON w.super_id = i.super_id
),

-- 5) Booking confermati dal CRM
bookings AS (
  SELECT
    CAST(r.IndividualId AS STRING) AS IndividualId,
    CAST(h.ConfirmationDate AS DATE) AS confirmation_date
  FROM `silversea-293815.data_landing_raw.Azure_CRM_BkgRole` r
  JOIN `silversea-293815.data_landing_raw.Azure_CRM_BkgHdr` h
    ON r.BkgCod = h.BkgCod
  WHERE h.BkgStatus = 'BK'
),

-- 6) Per ogni WEBQ, primo booking confermato DOPO la WEBQ
webq_conversion AS (
  SELECT
    wi.funnel_step,
    wi.user_pseudo_id,
    wi.webq_date,
    MIN(b.confirmation_date) AS first_booking_after_webq
  FROM with_individual wi
  LEFT JOIN bookings b
    ON wi.IndividualId = b.IndividualId
   AND b.confirmation_date > wi.webq_date
  GROUP BY wi.funnel_step, wi.user_pseudo_id, wi.webq_date
),

-- 7) Aggregato WEBQ per step
webq_agg AS (
  SELECT
    funnel_step,
    COUNT(*)                              AS webq_count,
    COUNT(DISTINCT user_pseudo_id)        AS webq_users,
    COUNTIF(first_booking_after_webq IS NOT NULL) AS converted_webq,
    ROUND(AVG(DATE_DIFF(first_booking_after_webq, webq_date, DAY)), 1) AS avg_days_to_booking
  FROM webq_conversion
  GROUP BY funnel_step
)

-- OUTPUT: una riga per step
SELECT
  a.funnel_step,
  v.visitors,
  a.webq_users,
  a.webq_count,
  a.converted_webq,
  ROUND(SAFE_DIVIDE(a.converted_webq, a.webq_users) * 100, 2) AS webq_to_booking_pct,
  a.avg_days_to_booking
FROM webq_agg a
LEFT JOIN step_visitors v USING (funnel_step)
ORDER BY
  CASE a.funnel_step WHEN 'guests WEBQ' THEN 1 WHEN 'category WEBQ' THEN 2 WHEN 'fare WEBQ' THEN 3 END;


-- =============================================================================
-- DIAGNOSTICA: valori reali di voyage_funnel_step_name sulle WEBQ
-- (utile a inizio analisi per confermare le label)
-- =============================================================================
-- SELECT
--   (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'voyage_funnel_step_name') AS funnel_step,
--   COUNT(*) AS cnt
-- FROM `silversea-293815.analytics_256550454.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20251203' AND '20260228'
--   AND event_name = 'generate_lead_WEBQ'
-- GROUP BY funnel_step ORDER BY cnt DESC;
