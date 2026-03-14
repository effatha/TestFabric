# AWG_DWH - Pipeline Execution Order

## Microsoft Fabric Data Pipeline Architecture

---

## End-to-End Flow

```
External Sources
     │
     ▼
[BRONZE LAYER - Lakehouse]
     │  Notebooks + Data Pipelines
     ▼
[SILVER LAYER - Warehouse L0]
     │  Stored Procedures (SQL)
     ▼
[GOLD LAYER - Warehouse L1]
     │  Stored Procedures (SQL)
     ▼
[SEMANTIC LAYER - Views]
     │  PL_V_SALES and other views
     ▼
[BI TOOLS - Power BI / Excel]
```

---

## Pipeline 1: PRIO Daily Transactions (Main Pipeline)

**Trigger:** Daily schedule + on new file arrival in shortcut folder
**Frequency:** Multiple times per day (files arrive incrementally)

### Stage 1: Bronze Ingestion
| Step | Activity | Source → Target | Notes |
|------|----------|-----------------|-------|
| 1.1 | Notebook: `NB_BRONZE_LOAD_PRIO_CSV` | AWS S3 shortcut → `PRIO_CSV_SALES_TRANSACTION` | Handles encoding, special chars |
| 1.2 | Data Pipeline: Prio Order API | Prio API → `PRIO_API_ORDERS` | Lead pax names, emails |

### Stage 2: Bronze → Silver (ETL)
| Step | Procedure | Action | Old Equivalent |
|------|-----------|--------|---------------|
| 2.1 | `usp_L0_LoadPrioSalesTransaction` | Cleanse + MERGE Bronze → Silver | `vimport_prio_transaction_staging` dedup logic |
| 2.2 | `usp_L0_MergeSuppliers` | Upsert supplier surrogation | `usp_ProcessGeneralDimensions` (suppliers) |
| 2.3 | `usp_L0_MergeProducts` | Upsert product surrogation | `usp_ProcessGeneralDimensions` (products) |
| 2.4 | `usp_L0_MergeAgents` | Upsert agent surrogation | `usp_ProcessGeneralDimensions` (agents) |
| 2.5 | `usp_L0_MergeBookings` | Upsert booking entity + enrichment | `usp_ProcessBookings` |
| 2.6 | `usp_L0_MergeSalesTransactions` | Build transaction lines (Revenue, Discounts, Reprices) | `usp_ProcessPrioTransactions` |

### Stage 3: Silver → Gold (Analytics)
| Step | Procedure | Action | Old Equivalent |
|------|-----------|--------|---------------|
| 3.1 | `usp_L1_LoadDimensions` | Sync all Silver → Gold dimensions | (implicit in old flow) |
| 3.2 | `usp_L1_LoadFactSalesTransaction` | Build fact + agent commissions + exchange rates | `usp_ProcessPrioTransactions` + `usp_ProcessAgentCommissions` + `usp_ProcessExchangeRates` |

**Single entry point:** `EXEC usp_L1_OrchestratePrioLoad` (calls all above in order)

---

## Pipeline 2: Exchange Rates (Daily)

**Trigger:** Daily, before main Prio pipeline

| Step | Activity | Source → Target |
|------|----------|-----------------|
| 2.1 | Data Pipeline: BOE API | BOE API → `BOE_API_EXCHANGE_RATES` (Bronze) |
| 2.2 | Procedure: `usp_L0_LoadExchangeRates` | Bronze → `L0_EXCHANGE_RATES` (Silver) |

---

## Pipeline 3: Reference Data Sync (Daily)

**Trigger:** Daily (before Prio pipeline)

| Step | Activity | Source → Target |
|------|----------|-----------------|
| 3.1 | Data Pipeline: SharePoint | `MD_LIST_EXCHANGE_RATES` → `L0_EXCHANGE_RATES` |
| 3.2 | Data Pipeline: SharePoint | `MD_LIST_PRODUCTS` → `L0_SRG_PRODUCT` (enrichment columns) |
| 3.3 | Data Pipeline: SharePoint | `MD_LIST_AGENTS` → `L0_SRG_AGENT` (classification columns) |

---

## Pipeline 4: WordPress Transactions (FTIX + ATIX)

**Trigger:** Daily

| Step | Activity | Source → Target |
|------|----------|-----------------|
| 4.1 | Data Pipeline: MySQL shortcut | FTIX MySQL → `WP_FTIX_TRANSACTIONS` (Bronze) |
| 4.2 | Data Pipeline: MySQL shortcut | ATIX MySQL → `WP_ATIX_TRANSACTIONS` (Bronze) |
| 4.3 | Used by `usp_L0_MergeBookings` | Enriches bookings with WP created dates + CC attribution |

---

## Pipeline 5: OpenPass (Weekly / On-demand)

| Step | Activity | Source → Target | Old Equivalent |
|------|----------|-----------------|---------------|
| 5.1 | Notebook/Pipeline | OpenPass API → `OPENPASS_BOOKINGS` (Bronze) | `import_openpass_bookings` |
| 5.2 | Procedure: `usp_L0_LoadOpenPassReservations` | Bronze → Silver surrogation | `usp_ProcessOpenPassBookingsReservations` |
| 5.3 | Procedure: `usp_L0_LoadOpenPassPayments` | Bronze → Silver payments | `usp_ProcessOpenPassBookingsPayments` |
| 5.4 | Procedure: `usp_L0_ProcessOPCancellations` | Handle cancellations | `usp_ProcessOPBookingCancellation` |

---

## Pipeline 6: Agent Remits (On-demand)

| Step | Activity | Old Equivalent |
|------|----------|---------------|
| 6.1 | Procedure: `usp_L0_LoadAgentRemits` | `usp_ProcessAgentRemits` |

---

## Pipeline 7: Debtors Balance (Daily, after Prio pipeline)

| Step | Activity | Old Equivalent |
|------|----------|---------------|
| 7.1 | Procedure: `usp_L1_LoadDebtorsBalance` | `usp_ProcessDebtorsBalance` |

---

## Execution Schedule

| Time  | Pipeline | Priority |
|-------|----------|----------|
| 02:00 | Exchange Rates (BOE API) | High |
| 02:30 | Reference Data Sync (SharePoint) | High |
| 03:00 | WordPress (FTIX + ATIX) | Medium |
| 04:00 | Prio CSV Ingestion + Full ETL | High |
| 05:30 | Debtors Balance update | Low |
| 06:00 | OpenPass (Weekly on Monday) | Low |

---

## Error Handling Strategy

- Each procedure wrapped in `BEGIN TRY / CATCH`
- Errors logged to a `L0_PIPELINE_LOG` table (to be created)
- Fabric Data Pipeline alerts configured for failures
- The `FL_IS_PROCESSED` / `FL_IS_PROCESSED_TO_GOLD` flags prevent double-processing
- On error: fix root cause and re-run the failed step only

---

## Idempotency

All Silver procedures use `MERGE` patterns — safe to re-run.
The `FL_IS_PROCESSED = 0` filter in Silver, `FL_IS_PROCESSED_TO_GOLD = 0` in Gold
ensure only new/changed rows are processed each run.
For full reload: `EXEC usp_L1_OrchestratePrioLoad @bReload = 1`

---

## Key Design Decisions vs Old System

| Concern | Old System | New System |
|---------|-----------|------------|
| Staging | `import_prio_transaction_staging_v2` (SQL Server table) | `PRIO_CSV_SALES_TRANSACTION` (Lakehouse Delta) |
| Dedup | `vimport_prio_transaction_staging` view (RANK on-the-fly) | Done once in `usp_L0_LoadPrioSalesTransaction` |
| Processing flag | `bIsProcessed` bit on staging table | `FL_IS_PROCESSED` on `L0_PRIO_SALES_TRANSACTION` |
| Dimension store | Mixed `Dim*` tables in same DB | Separate `L0_SRG_*` (Silver) + `L1_DIM_*` (Gold) |
| Fact table | Single `FactPrioSales` (with exchange rates mixed in) | `L0_SRG_SALES_TRANSACTION` (pre-rate) + `L1_FACT_SALES_TRANSACTION` (with rates) |
| Exchange rates | In-place UPDATE on fact table | Applied in Gold load procedure |
| Backups | 40+ `_bck` tables in same DB | Lakehouse Delta time-travel (30-day history) |
| Monitoring | `ImportExecutions` table | Fabric monitoring + `L0_PIPELINE_LOG` |
