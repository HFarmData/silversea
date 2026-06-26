# EJ — Giorni di anticipo della visita rispetto alla partenza

## Obiettivo
Misurare di quanti giorni in **anticipo** rispetto alla data di partenza della crociera
(`p_departure_date`) gli utenti visitano:
- **Itinerary Page**: `page_view`, URL contiene `journeys/`, NON match `my-explora|about`;
- **Funnel**: `page_view`, URL contiene `booking.explorajourneys.com/touchb2c`.

Output: media, mediana, distribuzioni e spaccato per **destinazione** (`p_sub_category`, la macro
destinazione, es. `car` = Caraibi).

`days_before_departure = DATE_DIFF(departure_date, visit_date, DAY)` (positivo = visita prima
della partenza).

## Query
1. `01_global.sql` — media e mediana globali per page group.
2. `02_by_destination.sql` — stesso calcolo spaccato per `p_sub_category` (con eredità per il Funnel).
3. `03_distribution.sql` — distribuzione a fasce dei giorni di anticipo per page group.
4. `04_distribution_by_destination.sql` — distribuzione a fasce per page group **e** destinazione.

## Due insidie chiave (vedi docs)
1. **Doppio formato data**: `p_departure_date` è `yyyy-MM-dd` sulle Itinerary Page e `dd-MM-yyyy`
   sul Funnel → parsing con `SAFE.PARSE_DATE` su entrambi i formati.
2. **Overlap URL**: gli URL del Funnel contengono `journeys/` → nel `CASE` il **Funnel va prima**
   della Itinerary Page.

## Eredità di `p_sub_category` (solo Funnel)
I `page_view` del Funnel **non** portano `p_sub_category`. Si eredita dall'**ultima Itinerary Page**
visitata dallo stesso utente:
1. a livello **sessione** (`last_itin_session`, join su `user_pseudo_id` + `ga_session_id`);
2. fallback a livello **utente** (`last_itin_user`).
Le righe con `final_sub_category` nullo sono escluse dagli spaccati per destinazione.

> Approccio tentato e scartato: window function diretta per l'eredità (falliva); ha funzionato un
> LEFT JOIN esplicito con CTE basate su `ROW_NUMBER()`.

## Periodo
`_TABLE_SUFFIX BETWEEN '20250325' AND '20260325'` (placeholder nei file).

## Changelog
- Diagnostica iniziale per confermare il nome (`p_departure_date`) e i **formati** (scoperta della
  dualità di formato dopo media/mediana nulle sul Funnel).
- Fix dell'ordine del `CASE` (Funnel prima di Itinerary Page).
- Eredità `p_sub_category` per il Funnel: prima sessione, poi utente come fallback.
- Aggiunte distribuzioni a fasce e spaccato per destinazione.
- Trim progressivo: rimossi lo spaccato **per mese**, il dettaglio sub_category per mese, e il
  filtro di soglia per destinazione. Le 4 query finali nascono dallo split di un'unica query
  combinata con `UNION ALL`.
