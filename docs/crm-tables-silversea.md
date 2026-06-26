# Tabelle CRM Silversea & chiavi di join

Documentazione delle tabelle CRM e dei percorsi per collegare gli eventi GA4 ai dati CRM.

> ⚠️ **Caveat sul progetto**: le tabelle `data_landing_clean` e `data_landing_raw` stanno sotto
> **`silversea-293815`** (non `dm-2021-hdm-01`). In una query iniziale erano state referenziate
> per errore sotto `dm-2021-hdm-01` — usare sempre `silversea-293815`.

---

## Tabelle principali

| Tabella | Contenuto |
|---------|-----------|
| `silversea-293815.data_landing_raw.Azure_CRM_BkgHdr` | Header dei booking (testata) |
| `silversea-293815.data_landing_raw.Azure_CRM_BkgRole` | Ruoli/individui associati a un booking |
| `silversea-293815.data_landing_raw.Azure_CRM_KPI_Ind` | KPI per individuo |
| `silversea-293815.data_landing_raw.Azure_CRM_WebRequest` | Richieste web (lead) registrate nel CRM |
| `silversea-293815.data_landing_clean.super_id` | Mappa super_id ↔ array di Google client id |
| `silversea-293815.data_landing_clean.super_id_latest_individual_id` | super_id ↔ ultimo IndividualId |

---

## Schemi noti (colonne rilevanti)

### `Azure_CRM_WebRequest`
`IndividualId` (INT64), `RequestTypology` (STRING), `Date` (TIMESTAMP), `Destination`, `Ship`,
`Detail`, `Note`, `MarketingEffort`, `BrochureRequested`, `RequestType`, `RequestSubType`,
`SuiteCategory`, `Voyage`, `WRCod`, `SourceId` (INT64), `WorkingWithAgent`, `OriginalId`,
`NewMarketingEffort`, **`uwrid`** (STRING), `areacod`, più colonne tecniche `_inputFile`,
`_loadingTs`, `_lastModifiedTs`.

### `Azure_CRM_BkgRole`
`IndividualId` (INT64), `BkgCod` (codice booking, chiave verso BkgHdr).

### `Azure_CRM_BkgHdr`
`BkgCod`, `BkgStatus` (valore booking confermato = **`'BK'`**), `ConfirmationDate`.

### `super_id`
`super_id`, `google_ids` (**array** di client id GA4).

### `super_id_latest_individual_id`
`super_id`, `latest_individual_id`, `timestamp`.

---

## Catene di join GA4 → CRM

### A) Via `super_id` (catena "ufficiale")

```
user_pseudo_id
  → super_id.google_ids            (array: usare  user_pseudo_id IN UNNEST(s.google_ids))
  → super_id_latest_individual_id.latest_individual_id
  → Azure_CRM_BkgRole.IndividualId
  → Azure_CRM_BkgHdr  (BkgStatus = 'BK')   ← booking confermato
```

Esempio booking confermati:

```sql
SELECT
  CAST(r.IndividualId AS STRING) AS IndividualId,
  CAST(h.ConfirmationDate AS DATE) AS confirmation_date
FROM `silversea-293815.data_landing_raw.Azure_CRM_BkgRole` r
JOIN `silversea-293815.data_landing_raw.Azure_CRM_BkgHdr` h
  ON r.BkgCod = h.BkgCod
WHERE h.BkgStatus = 'BK'
```

> **Copertura**: la catena super_id ha **gap di copertura** importanti. Sul sottoinsieme delle
> WEBQ produce risultati prossimi allo zero. Resta l'approccio più corretto concettualmente ma
> poco affidabile sui volumi → vedi `silversea/01-webq-funnel-crm-linking/`.

### B) Via `uwrid` — ❌ VICOLO CIECO

Idea: `generate_lead_WEBQ` (param `uwrid`) → `Azure_CRM_WebRequest.uwrid` → `IndividualId` → …

**Non funziona**: gli `uwrid` in GA4 e nel CRM sono **generati in modo indipendente** e non si
incrociano (test su campione: **0 match**). Documentato come dead-end, da non riusare.

### C) `IndividualId` dall'URL (regex)

Quando l'utente arriva da email con `IndividualId` in querystring, si estrae direttamente:

```sql
REGEXP_EXTRACT(raw_url, r'IndividualId=(\d+)')   -- solo cifre
-- REGEXP_EXTRACT(raw_url, r'IndividualId=(\w+)') -- se può contenere lettere/underscore
```

Permette di saltare la catena super_id quando l'IndividualId è già nell'URL.

---

## Note sui lead vs booking

- Gli eventi GA4 `generate_lead_*` tracciano **lead ecommerce**, NON i booking confermati nel CRM.
  Per "booking reale" usare sempre `Azure_CRM_BkgHdr` con `BkgStatus = 'BK'`.
- Per il **tempo di conversione** WEBQ→booking: differenza tra il timestamp/`event_date` della
  WEBQ in GA4 e la `ConfirmationDate` del booking nel CRM.
- Nelle analisi di funnel, considerare conversione **solo i booking confermati DOPO** la data
  della WEBQ (non i booking storici preesistenti).

---

## Identificazione VS (Voyage Selection)

I contatti VS arrivano da campagne email con tag `_VS_`:

```sql
LOWER(raw_url) LIKE '%utm_medium=email%' AND raw_url LIKE '%_VS_%'
```

Spesso vanno **esclusi** dalle analisi di nuovi prospect (sono già in database/contattati).
