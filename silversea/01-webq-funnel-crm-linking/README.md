# Silversea — Funnel WEBQ + linking CRM

## Obiettivo
Analizzare il booking funnel via eventi **WEBQ** (richiesta preventivo) sui tre step, e collegare
le WEBQ ai **booking confermati nel CRM** per misurare la conversione.

## File
1. `webq_funnel_steps.sql` — per ciascuno step: visitatori, utenti con WEBQ, WEBQ lasciate,
   conversione a booking (CRM) e tempo medio WEBQ→booking.
2. `crm_linking_attempts.sql` — **documentazione dei tentativi di linking** GA4↔CRM, inclusi i
   vicoli ciechi (uwrid) e i limiti di copertura (super_id), con le diagnostiche usate.

## Step del funnel (`voyage_funnel_step_name`)
- Visitatori dello step (denominatore): `page_view` con valore `guests` / `category` / `fare`.
- Evento WEBQ sullo step: `generate_lead_WEBQ` con valore `guests WEBQ` / `category WEBQ` /
  `fare WEBQ`.

Volumi WEBQ registrati (dic 2025 – feb 2026): `guests WEBQ` 3.842, `category WEBQ` 2.374,
`fare WEBQ` 1.664 (più una manciata di valori spuri senza " WEBQ").

## Conversione a booking (CRM)
Catena: `user_pseudo_id` → `super_id.google_ids` → `super_id_latest_individual_id` →
`Azure_CRM_BkgRole` → `Azure_CRM_BkgHdr` (`BkgStatus = 'BK'`). Si considera conversione **solo** un
booking confermato **dopo** la data della WEBQ (`ConfirmationDate > webq_date`), non i booking
storici. Vedi `docs/crm-tables-silversea.md`.

## Linking GA4↔CRM — stato (IRRISOLTO / parziale)
- **uwrid**: ❌ vicolo cieco. `generate_lead_WEBQ.uwrid` → `Azure_CRM_WebRequest.uwrid` dà **0
  match**: gli uwrid sono generati in modo indipendente nei due sistemi.
- **super_id**: catena corretta ma con **gap di copertura** (risultati prossimi a zero sul
  sottoinsieme WEBQ). È l'approccio usato in `webq_funnel_steps.sql`, ma i numeri di conversione
  vanno letti con cautela.
- **IndividualId da URL**: `REGEXP_EXTRACT(raw_url, r'IndividualId=(\d+)')` quando presente in
  querystring (es. arrivi da email) — bypassa la catena super_id.

## Periodo
Originale: 3 dic 2025 – 28 feb 2026 (`_TABLE_SUFFIX BETWEEN '20251203' AND '20260228'`).

## Changelog
- Confermato che i `generate_lead_*` tracciano lead ecommerce, non booking confermati → si usano
  le tabelle Azure per il booking reale.
- Confermato **WBCH** come hard action (non WBOF04).
- Conversione = solo booking confermati **dopo** la WEBQ.
- Tentato uwrid → 0 match (scartato). Riportato alla catena super_id, con copertura limitata.
- Corretta la location delle tabelle: `data_landing_*` sotto `silversea-293815` (non `dm-2021-hdm-01`).
