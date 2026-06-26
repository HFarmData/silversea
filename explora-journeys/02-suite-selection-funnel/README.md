# EJ — Funnel Suite Selection

## Obiettivo
Una **riga per utente** a partire dal suo **primo Suite Selection** (`page_view` con URL
`/booking?step=suites`). Per ciascun utente estrae:
- `p_journey_code` dello step di partenza (per il flag reingresso);
- i **10 touchpoint successivi** (`pv_1` … `pv_10`), considerando page_view "rilevanti" anche gli
  eventi azione RAC, RAQ, Brochure, BH;
- **flag 0/1** di conversione avvenuti **dopo** lo step di partenza, **nella stessa sessione**:
  RAC, RAQ, Brochure, BH, Purchase, reingresso a funnel con viaggio diverso.

`pv_0` = URL dello stesso Suite Selection.

## Scoping
Tutto (10 PV + flag) è scoped alla **stessa sessione GA4** (`ga_session_id`) e **successivo** al
timestamp del Suite Selection. Il join su `user_pseudo_id` + `ga_session_id` equivale a usare un
`visit_id` concatenato (vedi `docs/ga4-schema-notes.md`).

## Definizioni eventi (in questa analisi)
- **RAC**: `request_call_back_confirmation`
- **RAQ**: `request_quote_confirmation`
- **Brochure**: `request_brochure_confirmation`
- **BH**: `generate_lead` AND `lead_name='booking'` AND `payment_type='free'` AND
  `booking_status='option'` (tutto in AND) — ⚠️ definizione più stringente rispetto all'analisi
  sessioni/giorni.
- **Purchase**: `purchase` AND `p_journey_is_destex='NO'` AND `payment_type != 'total'`
- **Reingresso viaggio diverso**: `begin_checkout` con `p_journey_code` diverso da quello del
  Suite Selection.

## Valori delle colonne pv_1..pv_10
- per i `page_view`: l'**URL** della pagina;
- per gli eventi azione (RAC/RAQ/Brochure/BH): l'**etichetta** dell'evento (es. `RAC`, `BH`).

## Esclusione
Sono **esclusi** gli utenti che hanno visitato un URL contenente `my-explora` nella **stessa
sessione** e **prima** del timestamp del Suite Selection (CTE `users_to_exclude` + `NOT EXISTS`).

## Periodo
Originale: 2–14 aprile 2026. Nei file è un placeholder.

## Output noto (periodo 2–14 apr 2026)
Totale utenti: **15.330**. Flag: RAC=3, RAQ=96, Brochure=24, BH=129, Purchase=24,
Reingresso=1.661, almeno un flag=1.862, nessun flag=13.468. Validato contro la timeline reale di
un utente su 12 sessioni (scoping di sessione corretto).

## Changelog
- **Get Your Summary**: rimosso dallo scope (tracciamento non disponibile).
- **Colonne `pv_type`**: introdotte e poi **rimosse**; al loro posto i `pv_x` mostrano l'etichetta
  evento per le azioni e l'URL per i page_view.
- **`pv_0`**: aggiunto (URL del Suite Selection) catturando `ss_page_url`.
- **Esclusione `my-explora`**: aggiunta come CTE `users_to_exclude` + filtro `NOT EXISTS` su
  `first_suite`.
- Validazione su volumi e su `p_journey_code` (95,4% su Suite Selection, 92% su `begin_checkout`).
