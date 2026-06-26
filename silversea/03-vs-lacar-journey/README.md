# Silversea — Journey VS / mercato LACAR

## Obiettivo
Analizzare i contatti del mercato **LACAR** (Latin America / Caribbean) **escludendo i contatti
VS** (già in DB / contattati via campagna email Voyage Selection), per segmentarli in:
- **Prospect** — 2+ lead e nessuna conversione;
- **New in DB** — 1 solo lead e nessuna conversione;
- **Con conversione** — almeno un booking confermato nel CRM (`BkgStatus = 'BK'`).

## File
- `lacar_prospect_segmentation.sql` — query definitiva di segmentazione (output a 4 categorie con
  totale di controllo).

## Logiche chiave
- **`IndividualId` dall'URL**: `REGEXP_EXTRACT(raw_url, r'IndividualId=(\d+)')` (gli utenti email
  arrivano con l'IndividualId in querystring → si salta la catena super_id).
- **Esclusione VS**: `LOWER(raw_url) LIKE '%utm_medium=email%' AND raw_url LIKE '%_VS_%'`.
- **Conversione**: presenza nel CRM con `Azure_CRM_BkgHdr.BkgStatus = 'BK'` (join via
  `Azure_CRM_BkgRole.BkgCod`).
- Un utente con **più booking** (alcuni prima, alcuni dopo il contatto) può finire in più conteggi:
  per questo la classificazione è **per IndividualId** con un flag `has_conversion` unico, così la
  somma delle categorie torna con il totale.

## Approccio "journey dataset" a 10 pagine (progettato, non finalizzato)
In parallelo era stato impostato il disegno di un **dataset di journey** per leggere il percorso
degli utenti:
- colonne `page_1` … `page_10` con la sequenza delle pagine viste;
- **dedup dei refresh**: se due pagine consecutive sono uguali, si riporta la pagina successiva
  diversa (altrimenti la journey è falsata); le colonne restano vuote se il percorso è più corto;
- flag di sessione: **`has_FE`** (ha fatto una Funnel Entry, rilevata se l'URL contiene
  `quote.silversea.com` → permette il check sul KPI FE senza ricontarle dalle 10 pagine), più
  `has_WBBK`, `has_WBOF_01`…`has_WBOF_04`, `has_WEBQ`, `has_RAB`, `has_RAQ`, `has_SFO` (presenza dei
  rispettivi `generate_lead_*` nella sessione).

È un **approccio di design** (non una query definitiva consolidata) e va completato/validato prima
dell'uso; è documentato qui per non perderne la traccia.

## Periodo
Originale: gennaio 2026 (`_TABLE_SUFFIX BETWEEN '20260101' AND '20260131'`). Placeholder nel file.

## Changelog
- Aggiunto filtro di esclusione VS (`utm_medium=email` + `_VS_`).
- Estrazione `IndividualId` da URL via regex (al posto della catena super_id).
- Corretta la classificazione per evitare doppi conteggi (utenti con più booking): logica
  `total_leads` + `has_conversion` per IndividualId, con totale di controllo.
- Disegnato (non finalizzato) il journey dataset a 10 pagine con dedup refresh e flag di sessione.
