-- =============================================================================
-- SILVERSEA — TENTATIVI DI LINKING GA4 <-> CRM (documentazione + diagnostiche)
-- =============================================================================
-- Questo file documenta gli approcci provati per collegare gli eventi GA4
-- (in particolare generate_lead_WEBQ) ai booking confermati nel CRM, inclusi i
-- VICOLI CIECHI. Le query sono pensate come diagnostiche, non come pipeline finale.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- APPROCCIO A — Catena super_id  (CORRETTO ma con GAP DI COPERTURA)
-- -----------------------------------------------------------------------------
-- user_pseudo_id -> super_id.google_ids -> super_id_latest_individual_id
--   -> Azure_CRM_BkgRole -> Azure_CRM_BkgHdr (BkgStatus='BK')
-- Sul sottoinsieme WEBQ la copertura e' risultata prossima allo zero.
-- Diagnostica di copertura: quanti user_pseudo_id WEBQ trovano un super_id / IndividualId.

WITH webq_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `silversea-293815.analytics_256550454.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20251203' AND '20260228'   -- << IMPOSTA PERIODO
    AND event_name = 'generate_lead_WEBQ'
    AND user_pseudo_id IS NOT NULL
)
SELECT
  COUNT(*) AS webq_users_tot,
  COUNTIF(s.super_id IS NOT NULL) AS con_super_id,
  COUNTIF(i.latest_individual_id IS NOT NULL) AS con_individual_id
FROM webq_users w
LEFT JOIN `silversea-293815.data_landing_clean.super_id` s
  ON w.user_pseudo_id IN UNNEST(s.google_ids)
LEFT JOIN `silversea-293815.data_landing_clean.super_id_latest_individual_id` i
  ON s.super_id = i.super_id;


-- -----------------------------------------------------------------------------
-- APPROCCIO B — uwrid   ❌ VICOLO CIECO (0 MATCH)
-- -----------------------------------------------------------------------------
-- Idea: generate_lead_WEBQ ha un param 'uwrid' che doveva combaciare con
-- Azure_CRM_WebRequest.uwrid. In realta' gli uwrid sono generati in modo
-- INDIPENDENTE nei due sistemi -> nessun match. NON riusare.
--
-- Diagnostica: conta i match tra uwrid GA4 e uwrid CRM.
--
-- WITH ga4_uwrid AS (
--   SELECT DISTINCT
--     (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'uwrid') AS uwrid
--   FROM `silversea-293815.analytics_256550454.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN '20251203' AND '20260228'
--     AND event_name = 'generate_lead_WEBQ'
--     AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'uwrid') IS NOT NULL
-- )
-- SELECT
--   (SELECT COUNT(*) FROM ga4_uwrid) AS uwrid_ga4_distinti,
--   COUNT(*) AS uwrid_in_match
-- FROM ga4_uwrid g
-- JOIN `silversea-293815.data_landing_raw.Azure_CRM_WebRequest` w
--   ON g.uwrid = w.uwrid;
-- -> Risultato osservato: uwrid_in_match = 0.


-- -----------------------------------------------------------------------------
-- APPROCCIO C — IndividualId dall'URL (quando presente in querystring)
-- -----------------------------------------------------------------------------
-- Per arrivi da email l'IndividualId puo' essere nell'URL. Si estrae con regex,
-- saltando la catena super_id. Utile per VS/LACAR (vedi silversea/03).
--
-- SELECT
--   REGEXP_EXTRACT(
--     (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'raw_url'),
--     r'IndividualId=(\d+)'
--   ) AS IndividualId,
--   COUNT(*) AS cnt
-- FROM `silversea-293815.analytics_256550454.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20251203' AND '20260228'
--   AND (SELECT ep.value.string_value FROM UNNEST(event_params) ep WHERE ep.key = 'raw_url') LIKE '%IndividualId=%'
-- GROUP BY IndividualId
-- ORDER BY cnt DESC;


-- -----------------------------------------------------------------------------
-- DIAGNOSTICA DI SUPPORTO — allineamento dei range temporali GA4 vs CRM
-- -----------------------------------------------------------------------------
-- Verifica che il periodo GA4 e quello dei booking/web request CRM si sovrappongano,
-- altrimenti i "non match" possono dipendere solo da finestre temporali diverse.
--
-- SELECT 'GA4 WEBQ'     AS fonte, MIN(PARSE_DATE('%Y%m%d', event_date)) AS dal, MAX(PARSE_DATE('%Y%m%d', event_date)) AS al
-- FROM `silversea-293815.analytics_256550454.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20251203' AND '20260228' AND event_name = 'generate_lead_WEBQ'
-- UNION ALL
-- SELECT 'CRM WebRequest', MIN(CAST(Date AS DATE)), MAX(CAST(Date AS DATE))
-- FROM `silversea-293815.data_landing_raw.Azure_CRM_WebRequest`
-- UNION ALL
-- SELECT 'CRM BkgHdr (BK)', MIN(CAST(ConfirmationDate AS DATE)), MAX(CAST(ConfirmationDate AS DATE))
-- FROM `silversea-293815.data_landing_raw.Azure_CRM_BkgHdr` WHERE BkgStatus = 'BK';
