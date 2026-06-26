# Lezioni apprese & principi ricorrenti

Trappole e pattern emersi nelle analisi, da riusare e non re-imparare ogni volta.

---

## SQL / BigQuery

### `NOT IN` vs `NOT EXISTS`
`NOT IN` **fallisce silenziosamente con i NULL**: se la sottoquery contiene anche un solo NULL, la
condizione non filtra come atteso (restituisce risultati vuoti/incoerenti). Usare **`NOT EXISTS`**
come pattern di esclusione affidabile.

```sql
AND NOT EXISTS (
  SELECT 1 FROM users_multi_variation umv
  WHERE umv.user_pseudo_id = e.user_pseudo_id
)
```

### `SELECT DISTINCT` per deduplicare i conteggi di posizione
Nelle analisi di page path, una pagina vista più volte nella stessa sessione deve contare **una
volta**. `SELECT DISTINCT (user_pseudo_id, action_ts, session_position, page_url)` garantisce
"in quante sessioni la pagina è apparsa" e non "quanti page_view ci sono stati".

### Dedup di page view consecutive (lettura journey)
Per leggere correttamente la journey "page_1, page_2, …", se due page consecutive sono uguali
(refresh) si salta alla pagina successiva diversa, altrimenti la sequenza è falsata.

### Ordine dei `CASE` con pattern URL sovrapposti
Quando un pattern è sottoinsieme di un altro (es. URL del Funnel che contengono `journeys/`),
valutare prima il pattern più specifico. Vedi `docs/ga4-schema-notes.md`.

### Formati data multipli
Stesso parametro (`p_departure_date`) può avere formati diversi per dominio → `SAFE.PARSE_DATE`
su tutti i formati attesi con `CASE`.

---

## Statistica / metodo

### Mediana vs media (distribuzioni skewed)
Per "giorni/sessioni prima della conversione" la distribuzione è fortemente asimmetrica a destra:
molti convertono subito (mediana bassa, ~0–3 giorni), una coda lunga di "ripensatori" alza la
media (>10). **La mediana è più rappresentativa**; riportare comunque entrambe e una distribuzione
a fasce per mostrare la coda.

### Logica di reset per i multi-conversione (`LAG()`)
Se un utente converte più volte, **ogni conversione è un caso indipendente**: le sessioni/giorni
si contano a partire dalla conversione precedente, non dalla primissima visita. Implementato con
`LAG(event_timestamp) OVER (PARTITION BY user_pseudo_id, action_type ORDER BY event_timestamp)`
per ottenere `prev_action_ts` e filtrare la finestra.

### Ordinamento temporale nei test A/B (post-esposizione)
Le metriche di conversione devono contare **solo azioni avvenute dopo l'esposizione** (popup
visto / experiment viewed). In versioni precedenti azioni **pre-popup** finivano erroneamente nei
numeratori, gonfiando i risultati. Catturare `popup_seen_timestamp` (MIN) e confrontare
`event_timestamp > popup_seen_timestamp`. Lavorare inoltre a **livello utente** quando le
conversioni avvengono cross-session.

### Campionamento deterministico
Per estrarre N utenti random ma **riproducibili** (stesso campione a ogni run) e bilanciati per
variante:

```sql
ROW_NUMBER() OVER (PARTITION BY variation_id ORDER BY FARM_FINGERPRINT(user_pseudo_id))
```

---

## Machine Learning (propensity)

- **Split per UTENTE, non per riga**: evita data leakage (righe dello stesso utente in train e
  test contemporaneamente).
- **`_TABLE_SUFFIX` deve coprire anchor + finestra di predizione**: se il target guarda +14 giorni,
  la tabella deve arrivare almeno fino a `ultimo_anchor + 14gg`, altrimenti i target sono troncati.
- **Validazione out-of-time**: testare su un periodo successivo (es. mese seguente), non solo su
  uno split random dello stesso periodo, per valutare la robustezza reale.
- **Class imbalance**: `auto_class_weights = TRUE`; attendersi precision bassa e recall/lift alti
  (è un modello di clustering di propensione, non un classificatore puntuale).
- Una **feature inclusa nello scoring ma non nel training** viene ignorata dal modello (potenziale
  perdita di potere predittivo). Allineare le feature.

---

## CRM Silversea

- `generate_lead_*` = lead **ecommerce**, non booking confermati. Per booking reale →
  `Azure_CRM_BkgHdr.BkgStatus = 'BK'`.
- **WBCH** è la hard action corretta (non WBOF04).
- Linking GA4↔CRM: `uwrid` è un **vicolo cieco** (0 match, id indipendenti); la catena `super_id`
  è corretta ma con **gap di copertura**. Quando l'`IndividualId` è nell'URL, estrarlo via regex.
- Per i nuovi prospect, **escludere i contatti VS** (`utm_medium=email` + `_VS_`).

---

## Workflow & deliverable

- Approccio **diagnostico-first**: prima si validano nomi parametri, formati, volumi e strutture
  URL con query diagnostiche, poi si costruisce la logica finale.
- I deliverable finali erano tipicamente **Excel multi-foglio** (Summary, distribuzioni,
  breakdown, grafici) generati via Python/openpyxl, con formule che referenziano i totali del
  foglio Summary. Per scope **non inclusi in questa repo** (solo SQL + MD).
- Le query destinate ai colleghi vengono **separate in file standalone ben commentati** (commenti
  in italiano).
