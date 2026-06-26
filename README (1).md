# Analytics Repo — Explora Journeys & Silversea

Knowledge base delle analisi BigQuery (GA4 + CRM) per i due brand crocieristici luxury
**Explora Journeys (EJ)** e **Silversea**. Raccoglie le query definitive, la documentazione
delle tabelle, le note metodologiche e le lezioni apprese.

---

## Sorgenti dati principali

| Brand | Proprietà BigQuery GA4 |
|-------|------------------------|
| **Explora Journeys** | `ejattribution.analytics_268301381.events_*` |
| **Silversea** | `silversea-293815.analytics_256550454.events_*` |

Tabelle CRM Silversea: progetto `silversea-293815`, dataset `data_landing_raw` /
`data_landing_clean` (vedi [`docs/crm-tables-silversea.md`](docs/crm-tables-silversea.md)).

Modelli e tabelle di lavoro propensity: `dm-2021-hdm-01.Silversea_Playground.*`.

---

## Mappa della repo

```
analytics-repo/
├── explora-journeys/
│   ├── 01-preconversion-sessions-days/   Sessioni/giorni prima di BH e Purchase + page path a ritroso
│   ├── 02-suite-selection-funnel/        10 touchpoint post Suite Selection + flag conversione
│   ├── 03-days-before-departure/         Anticipo visita rispetto alla data di partenza
│   └── 04-ab-testing/                    A/B test popup "continue where you left" + utility varianti
├── silversea/
│   ├── 01-webq-funnel-crm-linking/       Funnel WEBQ + tentativi di linking GA4↔CRM
│   ├── 02-propensity-model/              Pipeline completa del propensity model (v3)
│   └── 03-vs-lacar-journey/              Customer journey VS / mercato LACAR + segmentazione
└── docs/
    ├── ga4-schema-notes.md               Parametri GA4, convenzioni, gotchas
    ├── crm-tables-silversea.md           Tabelle CRM + chiavi di join
    └── lessons-learned.md                Principi e trappole ricorrenti
```

Ogni sottocartella di analisi ha il suo `README.md` con: obiettivo, definizione degli
eventi/parametri usati, descrizione delle query, **changelog dettagliato** delle iterazioni
e output/risultati noti.

---

## Indice delle analisi

### Explora Journeys
1. **Pre-conversione: sessioni & giorni** — quante sessioni e quanti giorni passano prima di
   Booking Hold e Purchase, più una mappa pivot delle pagine viste nelle sessioni che precedono
   la conversione. Logica di reset con `LAG()` per i multi-conversione.
2. **Funnel Suite Selection** — una riga per utente a partire dal primo step "Suite Selection";
   10 touchpoint successivi e flag 0/1 di conversione (RAC, RAQ, Brochure, BH, Purchase,
   reingresso con viaggio diverso), tutto scoped alla stessa sessione GA4.
3. **Giorni di anticipo vs partenza** — di quanti giorni in anticipo, rispetto alla data di
   partenza della crociera (`p_departure_date`), gli utenti visitano Itinerary Page e pagine
   del Funnel; media, mediana, distribuzioni e spaccato per destinazione.
4. **A/B testing** — estrazione dell'esperimento popup `19_continue_where_you_left_v2` con
   metriche post-esposizione, più utility per rimuovere utenti esposti a più varianti.

### Silversea
1. **Funnel WEBQ + linking CRM** — step del booking funnel via WEBQ (guests/category/fare) e
   tentativi di collegare le WEBQ ai booking confermati nel CRM. Documenta anche i **vicoli
   ciechi** noti (uwrid a zero match, copertura super_id insufficiente).
2. **Propensity model** — pipeline completa (training, scoring, split, modello boosted tree,
   evaluate, predictions, segmentazione) per stimare la probabilità di conversione a 14 giorni.
3. **Journey VS / LACAR** — tracciamento dei clienti del mercato LACAR escludendo i contatti VS,
   con segmentazione prospect multi-lead vs nuovi in DB vs convertiti.

---

## Convenzioni

- **Lingua dei commenti**: italiano (per condivisione con colleghi meno esperti di SQL).
- **Date**: i range temporali nelle query sono **placeholder** (`'AAAAMMGG'` per `_TABLE_SUFFIX`,
  oppure commenti `-- << IMPOSTA PERIODO`). Dove il periodo originale ha rilevanza metodologica
  (es. propensity training vs scoring) è riportato nei commenti e nel changelog.
- **Versioni**: ogni file `.sql` contiene la **versione definitiva** della query. L'evoluzione
  (logiche/filtri cambiati) è tracciata nel changelog del README di ogni analisi.
- **Estrazione parametri**: pattern standard GA4
  `(SELECT value.string_value FROM UNNEST(event_params) WHERE key = '...')`.

> **Nota sui deliverable Excel**: le analisi terminavano spesso con file Excel multi-foglio
> generati via Python/openpyxl. Per scelta di scope questa repo contiene **solo SQL + documentazione**;
> gli script di export non sono inclusi.
