-- =============================================================================
-- SILVERSEA — SEGMENTAZIONE LACAR (esclusi VS): prospect / new in DB / convertiti
-- =============================================================================
-- Classifica gli IndividualId del mercato LACAR (esclusi i contatti VS) in:
--   - Prospect: 2+ lead, nessuna conversione
--   - New in DB: 1 lead, nessuna conversione
--   - Con conversione: almeno un booking CRM con BkgStatus='BK'
-- IndividualId estratto dall'URL; conversione dal CRM. Totale di controllo finale.
-- =============================================================================

WITH

-- 1) Lead da GA4 con IndividualId nell'URL, ESCLUDENDO i VS
leads_ga4 AS (
  SELECT
    REGEXP_EXTRACT(
      (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'raw_url'),
      r'IndividualId=(\d+)'
    ) AS IndividualId
  FROM `silversea-293815.analytics_256550454.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260101' AND '20260131'   -- << IMPOSTA PERIODO
    AND user_pseudo_id IS NOT NULL
    AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'raw_url') LIKE '%IndividualId=%'
    -- ESCLUDI VS
    AND NOT (
      LOWER((SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'raw_url')) LIKE '%utm_medium=email%'
      AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'raw_url') LIKE '%_VS_%'
    )
),

-- 2) Conteggio lead per IndividualId
lead_count AS (
  SELECT IndividualId, COUNT(*) AS total_leads
  FROM leads_ga4
  WHERE IndividualId IS NOT NULL
  GROUP BY IndividualId
),

-- 3) Utenti con conversione nel CRM (booking BK)
users_with_conversion AS (
  SELECT DISTINCT CAST(b.IndividualId AS STRING) AS IndividualId
  FROM `silversea-293815.data_landing_raw.Azure_CRM_BkgRole` b
  JOIN `silversea-293815.data_landing_raw.Azure_CRM_BkgHdr` h
    ON b.BkgCod = h.BkgCod
  WHERE h.BkgStatus = 'BK'
),

-- 4) Classificazione per IndividualId (flag conversione unico -> niente doppi conteggi)
users_classified AS (
  SELECT
    lc.IndividualId,
    lc.total_leads,
    CASE WHEN c.IndividualId IS NOT NULL THEN 1 ELSE 0 END AS has_conversion
  FROM lead_count lc
  LEFT JOIN users_with_conversion c
    ON lc.IndividualId = c.IndividualId
)

-- OUTPUT: 4 categorie + totale di controllo
SELECT 'Prospect (2+ lead, no conversione)' AS categoria, COUNT(DISTINCT IndividualId) AS users
FROM users_classified WHERE total_leads >= 2 AND has_conversion = 0
UNION ALL
SELECT 'New in DB (1 lead, no conversione)', COUNT(DISTINCT IndividualId)
FROM users_classified WHERE total_leads = 1 AND has_conversion = 0
UNION ALL
SELECT 'Con conversione', COUNT(DISTINCT IndividualId)
FROM users_classified WHERE has_conversion = 1
UNION ALL
SELECT 'TOTALE LACAR con lead (no VS)', COUNT(DISTINCT IndividualId)
FROM users_classified;
