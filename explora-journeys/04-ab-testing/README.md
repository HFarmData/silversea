# EJ — A/B testing

## File
1. `continue_where_you_left.sql` — estrazione completa dell'esperimento popup
   `19_continue_where_you_left_v2`: esposizione, popup visto, metriche di conversione **generali**
   e **post-popup**, con campionamento opzionale di 4.000 utenti per variante.
2. `remove_multi_variation_users.sql` — utility riusabile per **rimuovere gli utenti esposti a più
   di una variante** (richiesta cliente: ogni individuo deve aver visto al massimo una variante).

## Esperimento `19_continue_where_you_left_v2`
- **Esposizione**: `experiment_viewed` con `experiment_id = '19_continue_where_you_left_v2'`,
  variante in `variation_id`.
- **Popup visto**: `content_cta` con `cta_name = 'popup_funnel'` e `cta_type = 'popup_seen'`.
- **Click popup**: `content_cta` con `cta_name = 'return_to_funnel'`.
- **Funnel entry**: URL `booking.explorajourneys.com/touchb2c/`.
- **Booking Hold**: `generate_lead` + `lead_name = 'booking'`.
- **Purchase**: `purchase` + `p_journey_is_destex = 'NO'` + `payment_type != 'total'`.

## Regola dell'ordinamento temporale (post-popup)
Le metriche esistono in **due versioni**:
- **Generali** (indipendenti dal tempo): l'azione è avvenuta in qualunque momento.
- **Post-popup**: solo azioni con `event_timestamp > popup_seen_timestamp` (primo popup visto).

Le versioni precedenti contavano erroneamente azioni **pre-popup** nei numeratori. Si lavora a
livello utente (`popup_seen_timestamp = MIN(...)`) perché le conversioni avvengono cross-session.

## Esclusione varianti multiple
CTE `users_multi_variation` (utenti con `COUNT(DISTINCT variation_id) > 1`) esclusi con
**`NOT EXISTS`** (e non `NOT IN`, che fallisce con i NULL).

## Campionamento deterministico
4.000 utenti per variante, riproducibili e bilanciati:
`ROW_NUMBER() OVER (PARTITION BY variation_id ORDER BY FARM_FINGERPRINT(user_pseudo_id))`.
"Deterministico" = rieseguendo si ottiene lo stesso campione (l'hash è stabile per utente).

## Periodo
Originale: 31/01/2026 – 01/03/2026 (`_TABLE_SUFFIX BETWEEN '20260131' AND '20260301'`). Placeholder
nei file.

## Changelog
- Sostituito `NOT IN` con `NOT EXISTS` nell'esclusione delle varianti multiple.
- Aggiunto ordinamento temporale → metriche generali + post-popup.
- Aggiunto campione 4k/variante con `FARM_FINGERPRINT`.
