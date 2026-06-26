# Silversea — Propensity Model (v3)

## Obiettivo
Stimare la **probabilità che un utente converta nei 14 giorni successivi** a una data di
riferimento (anchor), per **clusterizzare gli utenti in fasce di propensity** e differenziare le
azioni marketing.

Conversione (target v3) = l'utente genera `generate_lead_WBOF_01` nei 14 giorni successivi
all'anchor.

## Pipeline ed ordine di esecuzione
| Step | File | Output |
|------|------|--------|
| 1 | `01_training_dataset.sql` | `propensity_training_v3` (feature + target, anchor settimanali) |
| 2 | `02_scoring_dataset.sql`  | `propensity_scoring_apr_2025_v3` (feature, anchor giornalieri apr 2025) |
| 3 | `03_train_test_split.sql` | `propensity_split_full_v3` (split 80/20 **per utente**) |
| 4 | `04_model.sql`            | `propensity_model_v3` (BOOSTED_TREE_CLASSIFIER) |
| 5 | `05_evaluate.sql`         | metriche ML.EVALUATE + lift per fascia |
| 6 | `06_predictions.sql`      | `propensity_predictions_apr_2025_v3` (+ `propensity_score`) |
| 7 | `07_segmentation.sql`     | crosstab utenti per fascia + flag comportamentali |

Tabelle/modelli nel progetto `dm-2021-hdm-01.Silversea_Playground`.

> ⚠️ **Provenienza dei file**: `03`–`07` sono gli **script verbatim** forniti. `01` e `02` sono
> **ricostruiti** dalla specifica v3 (i builder originali erano documenti separati). Le feature e
> la logica sono documentate, ma i pattern URL/param Silversea (pagine itinerario/destinazione,
> filtri FYC, sorgente `market`, formula `visits_trend`) vanno **verificati** sui builder originali
> dove segnalato con `-- << CONFERMARE`.

## Finestre temporali
- **Observation window**: 30 giorni precedenti l'anchor (feature).
- **Prediction window**: 14 giorni successivi l'anchor (target).
- **Training**: anchor settimanali Set 2024 – Mar 2025.
- **Scoring**: anchor giornalieri Aprile 2025.
- Filtri: `user_pseudo_id IS NOT NULL`, `ga_session_id IS NOT NULL`, `visits_30d > 0`.

> **`_TABLE_SUFFIX` deve coprire anchor + 14 giorni**: per il training, fino ad **aprile 2025**
> (`20240801`–`20250414`), non gennaio. Date come placeholder nei file, con valori originali nei
> commenti.

## Feature (26)
Provenienza: `visits_vs_count`, `visits_no_vs_count`.
Navigazione: `visits_7d`, `visits_14d`, `visits_30d`.
Content pages: `itinerary_page_visits_30d`, `destination_page_visits_30d`.
Engagement ripetuto: `max_same_itinerary_30d`, `max_same_destination_30d`.
Interazioni/lead: `filtri_fyc_30d`, `lead_rab_30d`, `lead_raq_30d`, `lead_sfo_30d`,
`lead_webq_30d`, `quote_page_visits_30d`.
Geo: `market`.
Feature V2: `days_since_last_visit`, `visits_trend`, `avg_pages_per_visit`, `has_lead_any`,
`quote_to_visit_ratio`, `multi_itinerary_interest`, `multi_destination_interest`.
Feature V3: `has_seen_guests_info_30d` (1 se URL contiene `quote.silversea.com` **e** `/guests-info`
nei 30 giorni precedenti).

## Modello
`BOOSTED_TREE_CLASSIFIER` (XGBoost), `input_label_cols = ['target_conversion']`,
`data_split_method = 'CUSTOM'` con `data_split_col = 'dataset_split'`, `max_iterations = 100`,
`learn_rate = 0.1`, `max_tree_depth = 6`, `subsample = 0.8`, `colsample_bytree = 0.8`,
`early_stop = TRUE`, `auto_class_weights = TRUE`, `l1_reg = 0.1`, `l2_reg = 1.0`.

## Performance (baseline v1, test set)
| Metrica | Valore | Note |
|---------|--------|------|
| ROC_AUC | **0.827** | ottimo per un propensity model |
| Recall | 68.6% | cattura ~69% dei converter |
| Precision | 1.9% | bassa ma attesa (clustering, classi sbilanciate) |
| Lift fascia Alta | **6.8x** | la fascia alta converte ~7x la media |

Distribuzione per fascia (v1): Alta (≥70%) 6,7% utenti / 46,1% conversioni / CR 3,56% / lift 6,8x;
Medio-Alta (40–70%) 23,0% / 34,7% / 0,79% / 1,5x; Media (20–40%) 21,4% / 11,0% / 0,27% / 0,5x;
Medio-Bassa (10–20%) 48,8% / 8,2% / 0,09% / 0,2x.

Top feature (importance): 1) `quote_page_visits_30d`, 2) `filtri_fyc_30d`,
3) `max_same_itinerary_30d`, 4) `itinerary_page_visits_30d`, 5) `visits_30d`.

## Problemi identificati ⚠️
1. **`_TABLE_SUFFIX` troncato**: nel training era `…'20250114'`, ma con anchor fino a marzo e
   target +14gg serve fino ad aprile (`'20250414'`). → corretto.
2. **`market` escluso dal training**: presente nello scoring/predictions ma non nella feature list
   del `CREATE MODEL` principale (vedi nota nei file). Il modello lo ignora → potenziale perdita di
   potere predittivo. Per usarlo davvero, riallenare includendolo coerentemente.
3. **Nessuna validazione out-of-time**: testato su uno split random 20% dello **stesso** periodo.
   Per la robustezza reale, validare su un periodo successivo (es. aprile 2025).

## Changelog
- **v1**: target = `generate_lead_WBOF_04` **OR** `generate_lead_WBOF_01`. Feature base
  (provenienza, navigazione, content, engagement, interazioni/lead).
- **v2**: aggiunte feature `days_since_last_visit`, `visits_trend`, `avg_pages_per_visit`,
  `has_lead_any`, `quote_to_visit_ratio`, `multi_itinerary_interest`, `multi_destination_interest`;
  introdotto `market`.
- **v3**: target ristretto a **solo `generate_lead_WBOF_01`**; aggiunta feature
  `has_seen_guests_info_30d`.
