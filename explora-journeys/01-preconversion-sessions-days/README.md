# EJ — Pre-conversione: sessioni & giorni + page path

## Obiettivo
Capire il comportamento degli utenti EJ **prima** delle due conversioni chiave:
- **Booking Hold (BH)**: `generate_lead` AND `lead_name = 'booking'`
- **Purchase**: `purchase` AND `p_journey_is_destex != 'YES'` AND `payment_type != 'total'`

Tre casistiche in output: **Booking Hold**, **Purchase**, **Any (OR)** (qualsiasi delle due).

Tre query:
1. `01_sessions_before.sql` — numero di sessioni prima della conversione (media, mediana, distribuzione).
2. `02_days_before.sql` — giorni prima della conversione (media, mediana, distribuzione a fasce).
3. `03_page_path_backward.sql` — pivot delle pagine viste nelle sessioni che precedono la conversione.

## Logica di reset (multi-conversione)
Se un utente converte più volte, **ogni conversione è indipendente**: le sessioni/giorni si
contano dalla conversione precedente dello stesso tipo (via `LAG()` → `prev_action_ts`), non
dalla primissima visita.

## Page path — indicizzazione a ritroso
Le sessioni sono numerate **all'indietro** dalla conversione:
- `session_minus_0` = sessione di conversione (solo page_view **prima** dell'evento di conversione).
- `session_minus_1` = sessione immediatamente precedente, … fino a `session_minus_X`.

Profondità **X**: **7** per Booking Hold, **10** per Purchase (mediane: BH≈2, Purchase≈4; X copre
quasi tutti i percorsi). Si lancia una volta per casistica, cambiando la soglia `QUALIFY` e il
filtro `action_type`.

## Periodi
- Azioni (BH/Purchase): `_TABLE_SUFFIX >= '20260101'` (dal 2026 in poi) nella versione originale.
- Sessioni: **tutto lo storico** (una conversione può seguire sessioni vecchie).
- Page view del page path: buffer ampio `BETWEEN '20251001' AND '20260428'` per catturare le
  sessioni pre-2026 della coda lunga.

> Date come placeholder nei file: impostare il periodo desiderato dove indicato.

## Output noto
- Sessioni medie / mediane (su tutto 2026): BH media ~5,3 / mediana 2; Purchase media ~8,6 /
  mediana 4; Any media ~5,8 / mediana 2.
- Giorni: mediana bassa (0–3) vs media alta (>10) → distribuzione skewed, coda lunga.
- Volumi conversioni di ordine di grandezza: BH ~6.276, Purchase ~1.611 (volumi bassi normali per
  fondo funnel luxury; verificati su `COUNT(DISTINCT user_pseudo_id)`).
- `page_url` è grezzo (con querystring) → decine di migliaia di righe; l'aggregazione per
  categoria di pagina si fa a valle (in Excel) con regex.

## Changelog
- **Correzione nomi parametri**: `e_lead_name` → `lead_name`; `c_payment_type` → `payment_type`
  (i prefissi `e_`/`c_` erano solo alias di output, non key GA4). `p_journey_is_destex` confermato
  con prefisso `p_`.
- **v1 (no reset)**: conteggio da prima visita assoluta alla prima azione per tipo. Sostituita
  perché non gestiva i multi-conversione.
- **v2 (reset con `LAG()`)**: ogni conversione indipendente → versione definitiva.
- **Distribuzioni**: aggiunte fasce (sessioni e giorni) dopo aver osservato mediana ≪ media.
- **Page path**: definita indicizzazione a ritroso (0 = conversione); session 0 troncata ai soli
  page_view pre-conversione; `SELECT DISTINCT` per contare una pagina/sessione una volta sola;
  `QUALIFY ROW_NUMBER()` per limitare la profondità; buffer `_TABLE_SUFFIX` allargato a Q4 2025
  per non perdere sessioni vecchie.
- Query separate e commentate in italiano per condivisione con colleghi.
