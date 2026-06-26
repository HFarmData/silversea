# Note sullo schema GA4 (Explora Journeys & Silversea)

Riferimenti tecnici sull'export BigQuery di GA4 usati trasversalmente nelle analisi.

---

## Tabelle

| Brand | Tabella |
|-------|---------|
| Explora Journeys | `ejattribution.analytics_268301381.events_*` |
| Silversea | `silversea-293815.analytics_256550454.events_*` |

Il suffisso `events_YYYYMMDD` si filtra con `_TABLE_SUFFIX`. Per coerenza si filtra **sempre**
anche su `event_date` quando si applica un range, perché un evento può finire nella tabella del
giorno successivo (fuso/late hits):

```sql
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND PARSE_DATE('%Y%m%d', event_date) BETWEEN '2025-01-01' AND '2025-01-31'
```

---

## Estrazione parametri da `event_params`

Pattern standard (scalar subquery su `UNNEST`):

```sql
(SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_url
(SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
```

### `visit_id`
Diverse query costruiscono un identificativo di sessione concatenando utente + sessione:

```sql
CONCAT(user_pseudo_id, CAST((SELECT s.value.int_value FROM UNNEST(event_params) s WHERE s.key = 'ga_session_id') AS STRING)) AS visit_id
```

È **funzionalmente identico** a fare il join su `user_pseudo_id` + `ga_session_id` separatamente,
perché `ga_session_id` è già unico per utente.

---

## Gotchas sui nomi dei parametri (Explora Journeys)

I prefissi `e_` / `c_` usati negli output **non** sono i nomi reali delle key in GA4. Validare
sempre prima di costruire la logica.

| Negli output / richieste | Key reale in `event_params` |
|--------------------------|------------------------------|
| `e_lead_name` | **`lead_name`** |
| `c_payment_type` | **`payment_type`** |
| `p_journey_is_destex` | `p_journey_is_destex` (il prefisso `p_` è reale) |

---

## Formati data: `p_departure_date` (EJ)

`p_departure_date` arriva in **due formati diversi a seconda del dominio**:

- Sito principale (Itinerary Page): `yyyy-MM-dd` (es. `2026-04-02`)
- Booking engine (Funnel): `dd-MM-yyyy` (es. `02-04-2026`)

Va parsato gestendo entrambi con `SAFE.PARSE_DATE`:

```sql
CASE
  WHEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%Y-%m-%d', raw_departure)
  WHEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure) IS NOT NULL THEN SAFE.PARSE_DATE('%d-%m-%Y', raw_departure)
END AS departure_date
```

---

## Overlap degli URL del Funnel (EJ)

Gli URL del Funnel (`booking.explorajourneys.com/touchb2c`) **contengono anch'essi `journeys/`**.
Quindi nel `CASE` di classificazione delle pagine il **Funnel va valutato PRIMA** della Itinerary
Page, altrimenti il funnel viene classificato come itinerary:

```sql
CASE
  WHEN page_url LIKE '%booking.explorajourneys.com/touchb2c%' THEN 'Funnel'
  WHEN page_url LIKE '%journeys/%'
       AND NOT REGEXP_CONTAINS(page_url, r'my-explora|about') THEN 'Itinerary Page'
END AS page_group
```

---

## Definizioni eventi — Explora Journeys

| Evento logico | Definizione GA4 |
|---------------|-----------------|
| **Itinerary Page** | `page_view`, URL contiene `journeys/` e NON match regex `my-explora\|about` |
| **Funnel** | `page_view`, URL contiene `booking.explorajourneys.com/touchb2c` |
| **Suite Selection** | `page_view`, URL contiene `/booking?step=suites` |
| **Booking Hold (BH)** — versione "sessioni/giorni" | `generate_lead` AND `lead_name = 'booking'` |
| **Booking Hold (BH)** — versione "funnel Suite Selection" | `generate_lead` AND `lead_name = 'booking'` AND `payment_type = 'free'` AND `booking_status = 'option'` |
| **Purchase** | `purchase` AND `p_journey_is_destex != 'YES'` (`= 'NO'`) AND `payment_type != 'total'` |
| **RAC** (Request A Call) | `event_name = 'request_call_back_confirmation'` |
| **RAQ** (Request A Quote) | `event_name = 'request_quote_confirmation'` |
| **Brochure** | `event_name = 'request_brochure_confirmation'` |
| **Reingresso a funnel** | `begin_checkout` con `p_journey_code` diverso da quello dello step di partenza |
| **Ingresso funnel** | `event_name = 'begin_checkout'` |

> ⚠️ **Attenzione**: la **BH ha due definizioni** diverse a seconda dell'analisi. Nell'analisi
> sessioni/giorni e nel page path basta `lead_name = 'booking'`; nell'analisi funnel Suite
> Selection si aggiungono `payment_type = 'free'` e `booking_status = 'option'`. Verificare quale
> serve nel contesto.

Copertura `p_journey_code` (diagnostica registrata): ~95,4% sugli eventi Suite Selection,
~92% su `begin_checkout`.

---

## Definizioni eventi — Silversea

Famiglia `generate_lead_*` (tracciano lead **ecommerce**, NON booking confermati nel CRM):

| Evento | Significato |
|--------|-------------|
| `generate_lead_WEBQ` | Web Quote (richiesta preventivo dal funnel voyage) |
| `generate_lead_WBOF_01` … `_04` | Web Booking Offer (step/varianti) — `WBOF_01` usato come target del propensity model v3 |
| `generate_lead_WBCH` | Web Booking Courtesy Hold — è la **hard action** corretta (non WBOF04) |
| `generate_lead_WBBK` | Web Booking (proxy ecommerce di booking; non conferma CRM) |
| `generate_lead_RAB` / `_RAQ` / `_SFO` | Request a Brochure / Quote / Send For Offer |

Step del booking funnel via parametro `voyage_funnel_step_name`:

- Page view dello step: valori `guests`, `category`, `fare`
- Evento WEBQ sullo step: valori `guests WEBQ`, `category WEBQ`, `fare WEBQ`

Parametro `uwrid` su `generate_lead_WEBQ`: Web Request ID, unico per evento (vedi
`docs/crm-tables-silversea.md` per il tentativo — fallito — di linking via uwrid).

Identificazione **VS** (contatti da campagna email "Voyage Selection"):

```sql
LOWER(raw_url) LIKE '%utm_medium=email%' AND raw_url LIKE '%_VS_%'
```

---

## Parametri A/B test

### Explora Journeys
- Esposizione: `event_name = 'experiment_viewed'`, parametri `experiment_id` e `variation_id`
  (es. `experiment_id = '19_continue_where_you_left_v2'`).
- Popup visto: `event_name = 'content_cta'`, `cta_name = 'popup_funnel'`, `cta_type = 'popup_seen'`.
- Click popup: `content_cta` con `cta_name = 'return_to_funnel'` (cta_click).

### Silversea
- Esposizione: `event_name = 'experiment_viewed'`, `experiment_id`
  (es. `19_drawer_pdp_scienze_comportamentali`).
- Test a livello componente: parametro `ab_component_tests` (JSON), es. variante "b" identificata
  da `LIKE '%payment-loading-progress%'` AND (`LIKE '%"s":"b"%'` OR `LIKE '%"segmentId":"b"%'`).

> **Regola d'oro A/B**: i flag di conversione vanno **temporalmente ordinati** (solo azioni
> avvenute DOPO l'esposizione/popup). Vedi `docs/lessons-learned.md`.
