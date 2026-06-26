# Documentazione Feature — Silversea Propensity Model v3

## Indice
1. [Introduzione](#introduzione)
2. [Feature Originali (v1)](#feature-originali-v1)
3. [Feature V2 (Derivate)](#feature-v2-derivate)
4. [Feature V3 (Nuove)](#feature-v3-nuove)
5. [Dimensioni Descrittive (Non-Predittive)](#dimensioni-descrittive-non-predittive)
6. [Variabile Target](#variabile-target)
7. [Finestre Temporali](#finestre-temporali)

---

## Introduzione

Il **Propensity Model v3** utilizza **24 feature** predittive organizzate in **5 categorie**:

| Categoria | N. Feature | Feature |
|-----------|-----------|---------|
| **Provenienza** | 2 | `visits_vs_count`, `visits_no_vs_count` |
| **Navigazione** | 3 | `visits_7d`, `visits_14d`, `visits_30d` |
| **Content Pages** | 2 | `itinerary_page_visits_30d`, `destination_page_visits_30d` |
| **Engagement Ripetuto** | 2 | `max_same_itinerary_30d`, `max_same_destination_30d` |
| **Interazioni/Lead** | 6 | `filtri_fyc_30d`, `lead_rab_30d`, `lead_raq_30d`, `lead_sfo_30d`, `lead_webq_30d`, `quote_page_visits_30d` |
| **Geografico** | 1 | `market` |
| **V2 Derivate** | 7 | `days_since_last_visit`, `visits_trend`, `avg_pages_per_visit`, `has_lead_any`, `quote_to_visit_ratio`, `multi_itinerary_interest`, `multi_destination_interest` |
| **V3 Nuove** | 1 | `has_seen_guests_info_30d` |

**Tutte le feature sono calcolate su una finestra di osservazione di 30 giorni precedenti la data di anchor.**

---

## Feature Originali (v1)

### Categoria: Provenienza

#### `visits_vs_count`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di sessioni distinte provenienti da **Silversea VS** (Silversea internal campaigns)
- **Come è calcolata**:
  - Conta i `ga_session_id` distinti filtrando gli eventi nei 30 giorni precedenti l'anchor
  - Seleziona solo gli eventi flaggati come `is_vs = TRUE`
  - Un evento è considerato VS quando:
    - `raw_url` contiene `utm_medium=email` (provenienza email)
    - E `raw_url` contiene `_VS_` (identificativo Silversea)
- **Formula SQL**:
  ```sql
  COUNT(DISTINCT IF(is_vs, ga_session_id, NULL))
  ```
- **Significato per il modello**: Misura quanto l'utente è esposto a campagne email dirette di Silversea
- **Range tipico**: 0 – 10+
- **Importanza**: Media

#### `visits_no_vs_count`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di sessioni distinte provenienti da **canali non-VS** (organic, paid search, direct, etc.)
- **Come è calcolata**:
  - Conta i `ga_session_id` distinti filtrando gli eventi nei 30 giorni precedenti l'anchor
  - Seleziona solo gli eventi flaggati come `is_vs = FALSE`
- **Formula SQL**:
  ```sql
  COUNT(DISTINCT IF(NOT is_vs, ga_session_id, NULL))
  ```
- **Significato per il modello**: Misura il traffico organico / da fonti esterne rispetto al traffico VS
- **Range tipico**: 0 – 20+
- **Importanza**: Media
- **Nota**: Utile per capire se l'utente proviene principalmente da campagne VS o ha un interesse organico

---

### Categoria: Navigazione

#### `visits_7d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di sessioni distinte negli **ultimi 7 giorni** precedenti l'anchor
- **Come è calcolata**:
  - Conta i `ga_session_id` distinti dove `event_date >= DATE_SUB(anchor_date, INTERVAL 7 DAY)`
  - Filtra solo gli eventi nei 30 giorni di observation window
- **Formula SQL**:
  ```sql
  COUNT(DISTINCT IF(event_date >= DATE_SUB(anchor_date, INTERVAL 7 DAY), ga_session_id, NULL))
  ```
- **Significato per il modello**: Misura la **recency** dell'engagement (quant'è recente l'ultimo accesso?)
- **Range tipico**: 0 – 5
- **Importanza**: Alta (viene utilizzato per calcolare `visits_trend`)

#### `visits_14d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di sessioni distinte negli **ultimi 14 giorni** precedenti l'anchor
- **Come è calcolata**:
  - Conta i `ga_session_id` distinti dove `event_date >= DATE_SUB(anchor_date, INTERVAL 14 DAY)`
  - Filtra solo gli eventi nei 30 giorni di observation window
- **Formula SQL**:
  ```sql
  COUNT(DISTINCT IF(event_date >= DATE_SUB(anchor_date, INTERVAL 14 DAY), ga_session_id, NULL))
  ```
- **Significato per il modello**: Misura l'engagement nei 2 settimane più recenti
- **Range tipico**: 0 – 10
- **Importanza**: Media-Alta

#### `visits_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di sessioni distinte negli **ultimi 30 giorni** precedenti l'anchor
- **Come è calcolata**:
  - Conta i `ga_session_id` distinti senza filtro temporale aggiuntivo (già dentro la CTE observation window)
  - Include tutte le visite dai 30 giorni precedenti all'anchor fino al giorno prima dell'anchor
- **Formula SQL**:
  ```sql
  COUNT(DISTINCT ga_session_id)
  ```
- **Significato per il modello**: Misura la **frequenza** globale di engagement (RFM - Recency, Frequency, Monetary)
- **Range tipico**: 1 – 50+
- **Importanza**: **Alta** (è tra le top 5 feature per importanza predittiva)
- **Filtro**: Il dataset finale esclude tutti i record con `visits_30d = 0`

---

### Categoria: Content Pages

#### `itinerary_page_visits_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di visite a **pagine di itinerari crociere** nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta tutti gli eventi dove `page_url LIKE '%/cruises/%'`
  - Applica il filtro su tutti gli eventi della observation window (30 giorni)
- **Formula SQL**:
  ```sql
  COUNTIF(is_itinerary_page)  -- dove is_itinerary_page = (page_url LIKE '%/cruises/%')
  ```
- **Significato per il modello**: Misura l'interesse esplicito per itinerari specifici di crociere
- **Range tipico**: 0 – 30+
- **Importanza**: **Alta** (è tra le top 5 feature per importanza predittiva)
- **Nota**: Ogni page view è conteggiata; se l'utente visita la stessa pagina di itinerario 5 volte, conta 5

#### `destination_page_visits_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di visite a **pagine di destinazioni** nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta tutti gli eventi dove `page_url LIKE '%/destinations/%'`
  - Applica il filtro su tutti gli eventi della observation window (30 giorni)
- **Formula SQL**:
  ```sql
  COUNTIF(is_destination_page)  -- dove is_destination_page = (page_url LIKE '%/destinations/%')
  ```
- **Significato per il modello**: Misura l'interesse per destinazioni / aree geografiche generiche
- **Range tipico**: 0 – 20+
- **Importanza**: Media
- **Nota**: Utile per distinguere browsing su itinerari vs. browsing su destinazioni

---

### Categoria: Engagement Ripetuto

#### `max_same_itinerary_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: **Numero massimo di visite allo STESSO itinerario** nei 30 giorni di osservazione
- **Come è calcolata**:
  1. Per ogni evento con `itinerary_id` non-null, estrae l'ID dell'itinerario dalla URL
     - Pattern: `REGEXP_EXTRACT(page_url, r'/cruises/([^/?]+)')` 
  2. Raggruppa gli eventi per `(user_pseudo_id, anchor_date, itinerary_id)` e conta
  3. Prende il massimo di questi conteggi
- **Formula SQL**:
  ```sql
  -- Step 1: Per ogni itinerario, conta le visite
  SELECT anchor_date, user_pseudo_id, itinerary_id, COUNT(*) AS cnt
  FROM events_with_pages WHERE itinerary_id IS NOT NULL
  GROUP BY anchor_date, user_pseudo_id, itinerary_id
  
  -- Step 2: Prendi il massimo per utente
  MAX(cnt) AS max_same_itinerary_30d
  ```
- **Significato per il modello**: Misura la **profondità di interesse** (l'utente torna più volte sullo stesso itinerario = forte interesse)
- **Range tipico**: 0 – 20+
- **Importanza**: **Alta** (è tra le top 5 feature per importanza predittiva)
- **Nota**: Un valore > 1 indica che l'utente sta valutando seriamente un itinerario

#### `max_same_destination_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: **Numero massimo di visite alla STESSA destinazione** nei 30 giorni di osservazione
- **Come è calcolata**:
  1. Per ogni evento con `destination_id` non-null, estrae l'ID della destinazione dalla URL
     - Pattern: `REGEXP_EXTRACT(page_url, r'/destinations/([^/?]+)')`
  2. Raggruppa gli eventi per `(user_pseudo_id, anchor_date, destination_id)` e conta
  3. Prende il massimo di questi conteggi
- **Formula SQL**:
  ```sql
  -- Step 1: Per ogni destinazione, conta le visite
  SELECT anchor_date, user_pseudo_id, destination_id, COUNT(*) AS cnt
  FROM events_with_pages WHERE destination_id IS NOT NULL
  GROUP BY anchor_date, user_pseudo_id, destination_id
  
  -- Step 2: Prendi il massimo per utente
  MAX(cnt) AS max_same_destination_30d
  ```
- **Significato per il modello**: Misura la **ricorrenza di interesse per destinazioni specifiche**
- **Range tipico**: 0 – 10+
- **Importanza**: Media
- **Nota**: Valore > 1 indica interesse ripetuto per una destinazione

---

### Categoria: Interazioni/Lead

#### `filtri_fyc_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di volte che l'utente ha utilizzato i **filtri "Find Your Cruise"** nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta gli eventi dove `event_name = 'find_your_cruise_filter'`
  - Filtra su tutti gli eventi della observation window (30 giorni)
- **Formula SQL**:
  ```sql
  COUNTIF(event_name = 'find_your_cruise_filter')
  ```
- **Significato per il modello**: Misura l'**engagement attivo** (l'utente sta cercando attivamente crociere)
- **Range tipico**: 0 – 20+
- **Importanza**: **Molto Alta** (è la feature #2 per importanza predittiva)
- **Nota**: Evento triggerato quando l'utente interagisce con i filtri di ricerca (date, destinazioni, prezzi, etc.)

#### `lead_rab_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di volte che l'utente ha generato l'evento **`generate_lead_RAB`** nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta gli eventi dove `event_name = 'generate_lead_RAB'`
- **Formula SQL**:
  ```sql
  COUNTIF(event_name = 'generate_lead_RAB')
  ```
- **Significato per il modello**: Misura i **lead generati tramite il form RAB** (Request A Brochure?)
- **Range tipico**: 0 – 5
- **Importanza**: Bassa-Media
- **Nota**: Parte della feature aggregata `has_lead_any` (v2)

#### `lead_raq_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di volte che l'utente ha generato l'evento **`generate_lead_RAQ`** nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta gli eventi dove `event_name = 'generate_lead_RAQ'`
- **Formula SQL**:
  ```sql
  COUNTIF(event_name = 'generate_lead_RAQ')
  ```
- **Significato per il modello**: Misura i **lead generati tramite il form RAQ** (Request A Quote?)
- **Range tipico**: 0 – 5
- **Importanza**: Bassa-Media
- **Nota**: Parte della feature aggregata `has_lead_any` (v2)

#### `lead_sfo_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di volte che l'utente ha generato l'evento **`generate_lead_SFO`** nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta gli eventi dove `event_name = 'generate_lead_SFO'`
- **Formula SQL**:
  ```sql
  COUNTIF(event_name = 'generate_lead_SFO')
  ```
- **Significato per il modello**: Misura i **lead generati tramite il form SFO** (possibilmente Silversea Form Opportunity?)
- **Range tipico**: 0 – 3
- **Importanza**: Bassa-Media
- **Nota**: Parte della feature aggregata `has_lead_any` (v2)

#### `lead_webq_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di volte che l'utente ha generato l'evento **`generate_lead_WEBQ`** nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta gli eventi dove `event_name = 'generate_lead_WEBQ'`
- **Formula SQL**:
  ```sql
  COUNTIF(event_name = 'generate_lead_WEBQ')
  ```
- **Significato per il modello**: Misura i **lead generati tramite il form WEBQ** (Web Quote?)
- **Range tipico**: 0 – 3
- **Importanza**: Bassa-Media
- **Nota**: 
  - Parte della feature aggregata `has_lead_any` (v2)
  - Correlato al target: spesso gli utenti che generano `lead_WEBQ` convertono a `generate_lead_WBOF_01`

#### `quote_page_visits_30d`
- **Tipo**: Intero (count)
- **Rappresenta**: Numero di visite a **pagine di quote** (`quote.silversea.com`) nei 30 giorni di osservazione
- **Come è calcolata**:
  - Conta tutti gli eventi dove `page_url LIKE '%quote.silversea.com%'`
- **Formula SQL**:
  ```sql
  COUNTIF(is_quote_page)  -- dove is_quote_page = (page_url LIKE '%quote.silversea.com%')
  ```
- **Significato per il modello**: Misura l'**engagement nel conversion funnel** (l'utente ha raggiunto il quotation tool)
- **Range tipico**: 0 – 10+
- **Importanza**: **Molto Alta** (è la feature #1 per importanza predittiva)
- **Nota**: Viene utilizzato per calcolare `quote_to_visit_ratio` (v2)

---

### Categoria: Geografico

#### `market`
- **Tipo**: Stringa (categoria)
- **Rappresenta**: **Mercato geografico** dell'utente (e.g., `US`, `EU`, `APAC`, `JP`, ecc.)
- **Come è calcolata**:
  - Estrae il valore del parametro `market` dagli event_params
  - Prende l'**ultimo valore non-null** durante la finestra di osservazione (30 giorni)
  - Ordinamento per timestamp decrescente (evento più recente vince)
- **Formula SQL**:
  ```sql
  -- Estrazione
  (SELECT ep.value.string_value FROM UNNEST(e.event_params) ep WHERE ep.key = 'market') AS market
  
  -- Aggregazione (ultimo valore)
  SELECT anchor_date, user_pseudo_id, market
  FROM (
    SELECT anchor_date, user_pseudo_id, market,
           ROW_NUMBER() OVER (PARTITION BY anchor_date, user_pseudo_id ORDER BY event_timestamp DESC) AS rn
    FROM events_with_pages WHERE market IS NOT NULL
  ) WHERE rn = 1
  ```
- **Significato per il modello**: Misura il **segmento geografico** dell'utente (utile per localizzare le campagne)
- **Range tipico**: `US`, `EU`, `APAC`, `JP`, `AU`, `CA`, etc. (dipende dalla configurazione Silversea)
- **Importanza**: Bassa
- **⚠️ Nota Importante**: 
  - **Feature presente nello scoring/predictions ma ASSENTE dal CREATE MODEL** → il modello la ignora
  - Per usarla davvero come predittore, va inclusa nella feature list del `CREATE MODEL` e il modello va riallenato

---

## Feature V2 (Derivate)

Le feature V2 sono calcolate **a partire dalle feature originali** e da altre aggregate. Introdotte nella v2 del modello.

#### `days_since_last_visit`
- **Tipo**: Intero (giorni)
- **Rappresenta**: **Numero di giorni trascorsi dall'ultima visita** fino all'anchor_date
- **Come è calcolata**:
  - Trova la data dell'ultimo evento nella observation window
  - Calcola la differenza in giorni rispetto all'anchor_date
- **Formula SQL**:
  ```sql
  DATE_DIFF(au.anchor_date, vf.last_visit_date, DAY) AS days_since_last_visit
  -- Dove last_visit_date = MAX(event_date) durante i 30 giorni precedenti l'anchor
  ```
- **Significato per il modello**: Misura la **recency** (quanto è "fresco" l'engagement?)
- **Range tipico**: 0 – 30
- **Importanza**: Media
- **Nota**: Valore 0-1 = visita recentissima (ieri o oggi), 15-30 = visita vecchia

#### `visits_trend`
- **Tipo**: Razionale (ratio, 0-1)
- **Rappresenta**: **Quota di visite negli ultimi 7 giorni rispetto al totale dei 30 giorni**
- **Come è calcolata**:
  - Divide `visits_7d` per `visits_30d`
  - Utilizza `SAFE_DIVIDE` per evitare divisioni per zero (risultato NULL se denominator è 0)
- **Formula SQL**:
  ```sql
  SAFE_DIVIDE(vf.visits_7d, vf.visits_30d) AS visits_trend
  ```
- **Significato per il modello**: Misura il **trend di engagement** recente
  - Valore alto (es. 0.8) = l'utente è molto attivo ultimamente
  - Valore basso (es. 0.2) = l'utente era attivo all'inizio del periodo ma meno ultimamente
- **Range tipico**: 0.0 – 1.0
- **Importanza**: Media-Alta
- **Nota**: Feature chiave per identificare utenti con trend in crescita vs. decay

#### `avg_pages_per_visit`
- **Tipo**: Razionale (ratio)
- **Rappresenta**: **Media di page_view per sessione** durante i 30 giorni di osservazione
- **Come è calcolata**:
  - Divide il totale dei `page_view` per il numero di sessioni distinte (`visits_30d`)
  - Utilizza `SAFE_DIVIDE` per evitare divisioni per zero
- **Formula SQL**:
  ```sql
  SAFE_DIVIDE(vf.page_views_30d, vf.visits_30d) AS avg_pages_per_visit
  ```
- **Significato per il modello**: Misura l'**engagement per sessione** (quanto approfondisce l'utente?)
  - Valore alto (es. 10) = sesioni lunghe e approfondite
  - Valore basso (es. 1-2) = sessioni quick-browse
- **Range tipico**: 1.0 – 15+
- **Importanza**: Media
- **Nota**: Discriminante tra browser casuali e serious shoppers

#### `has_lead_any`
- **Tipo**: Booleano (0 o 1)
- **Rappresenta**: **Flag indicante se l'utente ha generato almeno uno tra gli eventi di lead** (RAB, RAQ, SFO, WEBQ)
- **Come è calcolata**:
  - Somma i conteggi di `lead_rab_30d`, `lead_raq_30d`, `lead_sfo_30d`, `lead_webq_30d`
  - Se il totale è > 0, risultato = 1, altrimenti 0
- **Formula SQL**:
  ```sql
  IF(COALESCE(cp.lead_rab_30d, 0) + COALESCE(cp.lead_raq_30d, 0)
     + COALESCE(cp.lead_sfo_30d, 0) + COALESCE(cp.lead_webq_30d, 0) > 0, 1, 0) AS has_lead_any
  ```
- **Significato per il modello**: **Indicatore binario di intent** (l'utente ha manifestato intenzione di contatto?)
- **Range tipico**: 0 o 1
- **Importanza**: Media-Alta
- **Nota**: Feature categorica derivata (compressa da 4 feature numeriche)

#### `quote_to_visit_ratio`
- **Tipo**: Razionale (ratio, 0-1)
- **Rappresenta**: **Quota di visite a quote page rispetto al totale visite**
- **Come è calcolata**:
  - Divide `quote_page_visits_30d` per `visits_30d`
  - Utilizza `SAFE_DIVIDE` per evitare divisioni per zero
- **Formula SQL**:
  ```sql
  SAFE_DIVIDE(cp.quote_page_visits_30d, vf.visits_30d) AS quote_to_visit_ratio
  ```
- **Significato per il modello**: Misura il **focus conversionale** (quale percentuale del tempo l'utente passa nelle quote?)
  - Valore alto (es. 0.5) = l'utente è fortemente focalizzato sul quotation
  - Valore basso (es. 0.1) = il quotation è una piccola parte del browsing
- **Range tipico**: 0.0 – 1.0
- **Importanza**: Media
- **Nota**: Utile per distinguere intent: browsing vs. serious consideration

#### `multi_itinerary_interest`
- **Tipo**: Booleano (0 o 1)
- **Rappresenta**: **Flag indicante se l'utente ha visitato PIÙ DI UN itinerario distinto**
- **Come è calcolata**:
  - Conta il numero di `itinerary_id` distinti (per user_pseudo_id, anchor_date)
  - Se il conteggio > 1, risultato = 1, altrimenti 0
- **Formula SQL**:
  ```sql
  IF(COUNT(DISTINCT itinerary_id) > 1, 1, 0) AS multi_itinerary_interest
  ```
- **Significato per il modello**: Misura la **larghezza di considerazione**
  - Valore 1 = l'utente sta valutando multiple opzioni (comparazione attiva)
  - Valore 0 = l'utente è focalizzato su un singolo itinerario
- **Range tipico**: 0 o 1
- **Importanza**: Media
- **Nota**: Discriminante tra decisione focalizzata vs. fase di esplorazione

#### `multi_destination_interest`
- **Tipo**: Booleano (0 o 1)
- **Rappresenta**: **Flag indicante se l'utente ha visitato PIÙ DI UNA destinazione distinta**
- **Come è calcolata**:
  - Conta il numero di `destination_id` distinti (per user_pseudo_id, anchor_date)
  - Se il conteggio > 1, risultato = 1, altrimenti 0
- **Formula SQL**:
  ```sql
  IF(COUNT(DISTINCT destination_id) > 1, 1, 0) AS multi_destination_interest
  ```
- **Significato per il modello**: Misura la **versatilità di interesse geografico**
  - Valore 1 = l'utente sta esplorando più destinazioni (fase early browsing)
  - Valore 0 = l'utente è focalizzato su destinazioni specifiche
- **Range tipico**: 0 o 1
- **Importanza**: Media
- **Nota**: Correlato con `multi_itinerary_interest` ma cattura una dimensione diversa (destination vs. product)

---

## Feature V3 (Nuove)

#### `has_seen_guests_info_30d`
- **Tipo**: Booleano (0 o 1)
- **Rappresenta**: **Flag indicante se l'utente ha visitato la pagina "/guests-info" all'interno del quotation tool**
- **Come è calcolata**:
  - Identifica gli eventi dove:
    - `page_url LIKE '%quote.silversea.com%'` (è all'interno del quotation tool)
    - **E** `page_url LIKE '%/guests-info%'` (ha navigato alla sezione guest info)
  - Conta il massimo tra questi eventi (se > 0 → 1, altrimenti 0)
- **Formula SQL**:
  ```sql
  MAX(IF(is_guests_info, 1, 0)) AS has_seen_guests_info_30d
  -- Dove is_guests_info = (page_url LIKE '%quote.silversea.com%' AND page_url LIKE '%/guests-info%')
  ```
- **Significato per il modello**: Misura l'**avanzamento nel conversion funnel** (l'utente ha raggiunto la fase di compilazione guest info)
  - Valore 1 = l'utente è avanzato significantly nel funnel di quotazione (raccogli informazioni sugli ospiti)
  - Valore 0 = l'utente non ha raggiunto questa sezione
- **Range tipico**: 0 o 1
- **Importanza**: Alta (indicatore di seria intenzione di prenotazione)
- **Nota**: Feature v3 aggiunta per catturare l'avanzamento nel micro-funnel di quotazione

---

## Dimensioni Descrittive (Non-Predittive)

Le seguenti colonne sono estratte e incluse nel dataset ma **NON vengono utilizzate dal modello predittivo** (sono a scopo descrittivo/segmentazione):

#### `most_viewed_itinerary`
- **Tipo**: Stringa (ID itinerario)
- **Rappresenta**: L'**itinerario più visitato** durante i 30 giorni di osservazione
- **Come è calcolata**:
  - Raggruppa gli eventi per `itinerary_id` e conta le visite
  - Estrae l'ID con il massimo numero di visite (ROW_NUMBER + RANK DESC)
- **Significato**: Utile per **segmentazione post-modello** (quale itinerario preferisce l'utente?)
- **Utilizzo**: Nei file di segmentazione (`07_segmentation.sql`) per raggruppare utenti per itinerario

#### `most_viewed_destination`
- **Tipo**: Stringa (ID destinazione)
- **Rappresenta**: La **destinazione più visitata** durante i 30 giorni di osservazione
- **Come è calcolata**:
  - Raggruppa gli eventi per `destination_id` e conta le visite
  - Estrae l'ID con il massimo numero di visite
- **Significato**: Utile per **segmentazione post-modello** (quale destinazione preferisce l'utente?)
- **Utilizzo**: Nei file di segmentazione (`07_segmentation.sql`) per raggruppare utenti per destinazione

---

## Variabile Target

#### `target_conversion`
- **Tipo**: Booleano (0 o 1)
- **Rappresenta**: **Se l'utente ha generato l'evento `generate_lead_WBOF_01` nei 14 giorni SUCCESSIVI all'anchor_date**
- **Come è calcolata**:
  - Cerca eventi con `event_name = 'generate_lead_WBOF_01'`
  - Che cadono nella finestra: `anchor_date` → `DATE_ADD(anchor_date, INTERVAL 14 DAY)`
  - Se almeno un evento è trovato, assegna 1, altrimenti 0 (left join con NULL → 0)
- **Formula SQL**:
  ```sql
  SELECT DISTINCT a.anchor_date, e.user_pseudo_id, 1 AS target_conversion
  FROM events e
  CROSS JOIN anchor_dates a
  WHERE e.event_name = 'generate_lead_WBOF_01'
    AND e.user_pseudo_id IS NOT NULL
    AND PARSE_DATE('%Y%m%d', e.event_date) 
        BETWEEN a.anchor_date AND DATE_ADD(a.anchor_date, INTERVAL 14 DAY)
  ```
- **Significato**: La **conversione desiderata** nel modello (obiettivo predittivo)
- **Range**: 0 o 1
- **Bilanciamento**: Tipicamente **sbilanciato** (pochi convertitori, molti non-convertitori)
  - Training set: ~5-10% positivi
  - Gestione: `auto_class_weights = TRUE` nel modello per compensare lo sbilanciamento

---

## Finestre Temporali

### Definizione Temporale

Tutte le feature sono calcolate su una **finestra di osservazione fissa di 30 giorni**:

```
[anchor_date - 30 giorni] ←─────── observation window ─────→ [anchor_date - 1 giorno]
                          (30 giorni di storia)                (ultimo giorno incluso)
                                                                (anchor_date escluso)
```

### Esempi di Calcolo

**Esempio 1: Anchor = 2024-11-15**
- **Observation window**: 2024-10-16 → 2024-11-14 (30 giorni)
- **Prediction window**: 2024-11-15 → 2024-11-29 (14 giorni)
- Tutte le feature sono calcolate sui 30 giorni di osservazione
- Target = 1 se conversione avviene nei 14 giorni di predizione

**Esempio 2: Feature Timing**
- `visits_30d` = numero di sessioni distinte tra 2024-10-16 e 2024-11-14
- `visits_7d` = numero di sessioni distinte tra 2024-11-08 e 2024-11-14 (ultimi 7 giorni dell'observation window)
- `days_since_last_visit` = giorni tra l'ultima visita (max event_date) e 2024-11-15 (anchor)

### Training vs. Scoring

**Training Dataset** (`01_training_dataset.sql`):
- Anchor: **Settimanali** (Set 2024 – Mar 2025)
- _TABLE_SUFFIX: 20240801 – 20250414 (copre anchor + 14gg di predizione)
- Output: `propensity_training_v3` con ~15-20k record

**Scoring Dataset** (`02_scoring_dataset.sql`):
- Anchor: **Giornalieri** (Aprile 2025)
- _TABLE_SUFFIX: 20250302 – 20250513 (copre anchor + 14gg di predizione)
- Output: `propensity_scoring_apr_2025_v3` con ~30k record

---

## Riepilogo Importanza Feature

Basato su analisi dell'importanza nel modello XGBoost (v1/baseline):

| Rank | Feature | Importanza | Categoria |
|------|---------|-----------|-----------|
| 1 | `quote_page_visits_30d` | ★★★★★ | Interazioni/Lead |
| 2 | `filtri_fyc_30d` | ★★★★★ | Interazioni/Lead |
| 3 | `max_same_itinerary_30d` | ★★★★ | Engagement Ripetuto |
| 4 | `itinerary_page_visits_30d` | ★★★★ | Content Pages |
| 5 | `visits_30d` | ★★★★ | Navigazione |
| 6-10 | `visits_trend`, `avg_pages_per_visit`, `visit_7d`, `lead_webq_30d`, `has_lead_any` | ★★★ | Varie |
| 11-15 | `destination_page_visits_30d`, `multi_itinerary_interest`, `quote_to_visit_ratio`, `lead_rab_30d`, etc. | ★★ | Varie |
| 16+ | `market`, `lead_raq_30d`, `lead_sfo_30d` | ★ | Varie |

---

## Note Importanti ⚠️

1. **`market` non è utilizzato dal modello**: La feature è presente nello scoring ma assente dal `CREATE MODEL`. Per usarla, va inclusa e il modello va riallenato.

2. **Filtro su `visits_30d > 0`**: Il dataset finale esclude tutti gli utenti con zero visite nel periodo di osservazione (focus su engaged users only).

3. **Finestra temporale critica**: Il `_TABLE_SUFFIX` deve **coprire l'anchor + 14 giorni di predizione** altrimenti il target può essere incompleto.

4. **Nessun out-of-time validation**: Il modello è validato con uno split random 80/20 dello **stesso periodo** di training. Per robustezza reale, validare su un periodo futuro.

5. **Sbilanciamento classi**: Il dataset ha pochi convertitori (~5-10%). Il modello usa `auto_class_weights = TRUE` per compensare, ma attenzione alla Precision (bassa, ~1.9% baseline).

---

## Changelog Versioni

| Versione | Target | Feature Aggiunte | Feature Rimosse | Note |
|----------|--------|------------------|-----------------|------|
| **v1** | `generate_lead_WBOF_04` **OR** `generate_lead_WBOF_01` | Base (16) | – | Baseline originale |
| **v2** | Come v1 | 7 derivate (days_since_last_visit, visits_trend, avg_pages_per_visit, has_lead_any, quote_to_visit_ratio, multi_itinerary_interest, multi_destination_interest); + `market` | – | Focus su engagement recency e diversificazione |
| **v3** | **Solo `generate_lead_WBOF_01`** | `has_seen_guests_info_30d` (1) | – | Target ristretto; micro-funnel quotazione |

