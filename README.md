# AWG_DWH — Migration to Microsoft Fabric Medallion Architecture

## Overview

This project contains the migration plan and SQL artefacts for moving the **Attraction World (AWG)**
ticketing data warehouse from the legacy `PrioDW` SQL Server database to a modern
**Medallion Architecture (Bronze → Silver → Gold)** on **Microsoft Fabric**.

---

## What Was Analysed

The legacy `PrioDW` database contains:
- **122 tables** — only ~30 are actively used; the rest are backups, test tables, and superseded staging
- **45 views** — ~15 production views; rest are tests/backups
- **22 stored procedures** — all analysed; core ETL pipeline identified

See `00_analysis/` for the full breakdown of active vs deprecated objects.

---

## Architecture

```
BRONZE (Lakehouse - Delta Tables)          SILVER (Warehouse - L0)         GOLD (Warehouse - L1)
─────────────────────────────────         ──────────────────────────       ────────────────────────
PRIO_CSV_SALES_TRANSACTION         →      L0_PRIO_SALES_TRANSACTION        L1_DIM_DATE
PRIO_API_ORDERS                    →      L0_SRG_SUPPLIER                  L1_DIM_PRODUCT
BOE_API_EXCHANGE_RATES             →      L0_SRG_PRODUCT                   L1_DIM_SUPPLIER
MD_LIST_EXCHANGE_RATES             →      L0_SRG_AGENT                     L1_DIM_AGENT
MD_LIST_PRODUCTS (SharePoint)      →      L0_SRG_BOOKING                   L1_DIM_CHANNEL
MD_LIST_AGENTS (SharePoint)        →      L0_SRG_SALES_TRANSACTION         L1_DIM_RESELLER
WP_FTIX_TRANSACTIONS               →      L0_SRG_CHANNEL                   L1_FACT_SALES_TRANSACTION
WP_ATIX_TRANSACTIONS               →      L0_SRG_RESELLER
                                          L0_EXCHANGE_RATES
                                          L0_REF_INVOICE_STATUS
```

```
SEMANTIC LAYER
──────────────
PL_V_SALES  →  Power BI / Excel
```

---

## Directory Structure

```
├── 00_analysis/
│   ├── active_objects.md          ← Tables/views/SPs actively used (migrate these)
│   └── deprecated_objects.md      ← Backups, test tables, unused objects (skip)
│
├── bronze/
│   └── README.md                  ← Lakehouse setup: sources, ingestion method, schema
│
├── silver/
│   ├── tables/
│   │   ├── 01_L0_PRIO_SALES_TRANSACTION.sql   ← Cleansed Prio transaction staging
│   │   ├── 02_L0_SRG_SUPPLIER.sql             ← Supplier surrogation
│   │   ├── 03_L0_SRG_PRODUCT.sql              ← Product surrogation
│   │   ├── 04_L0_SRG_AGENT.sql                ← Agent surrogation
│   │   ├── 05_L0_SRG_BOOKING.sql              ← Booking surrogation
│   │   ├── 06_L0_SRG_SALES_TRANSACTION.sql    ← Sales transaction surrogation
│   │   ├── 07_L0_SRG_CHANNEL.sql              ← Channel surrogation
│   │   ├── 08_L0_SRG_RESELLER.sql             ← Reseller surrogation
│   │   ├── 09_L0_EXCHANGE_RATES.sql           ← Exchange rate reference
│   │   └── 10_L0_REF_INVOICE_STATUS.sql       ← Invoice status lookup (seeded)
│   │
│   └── procedures/
│       ├── 01_usp_L0_LoadPrioSalesTransaction.sql  ← Bronze→Silver: cleanse + MERGE
│       ├── 02_usp_L0_MergeSuppliers.sql            ← Upsert supplier dim
│       ├── 03_usp_L0_MergeProducts.sql             ← Upsert product dim
│       ├── 04_usp_L0_MergeAgents.sql               ← Upsert agent dim
│       ├── 05_usp_L0_MergeBookings.sql             ← Upsert booking entity
│       └── 06_usp_L0_MergeSalesTransactions.sql    ← Build transaction lines
│
├── gold/
│   ├── tables/
│   │   ├── 01_L1_DIM_DATE.sql                 ← Date dimension (with seed data)
│   │   ├── 02_L1_DIM_SUPPLIER.sql
│   │   ├── 03_L1_DIM_PRODUCT.sql
│   │   ├── 04_L1_DIM_AGENT.sql
│   │   ├── 05_L1_DIM_CHANNEL.sql
│   │   ├── 06_L1_DIM_RESELLER.sql
│   │   └── 07_L1_FACT_SALES_TRANSACTION.sql   ← Main analytics fact table
│   │
│   ├── procedures/
│   │   ├── 01_usp_L1_LoadDimensions.sql       ← Silver→Gold dim sync
│   │   ├── 02_usp_L1_LoadFactSalesTransaction.sql  ← Fact + exchange rates + P&L
│   │   └── 03_usp_L1_OrchestratePrioLoad.sql  ← Master orchestration (entry point)
│   │
│   └── views/
│       └── 01_PL_V_SALES.sql                  ← Public analytics view (→ Power BI)
│
└── orchestration/
    └── pipeline_execution_order.md             ← Full pipeline schedule + design decisions
```

---

## Key Design Decisions

### What Changed
| Old | New |
|-----|-----|
| Single SQL Server DB (`PrioDW`) | Three-layer Fabric workspace (Lakehouse + 2× Warehouse) |
| 40+ backup tables in same DB | Lakehouse Delta time-travel (30-day history) |
| `vimport_prio_transaction_staging` view for dedup | Dedup done once in Silver load SP |
| Mixed dimension+fact in one schema | Clear `L0_SRG_*` (Silver) / `L1_DIM_*` + `L1_FACT_*` (Gold) |
| Exchange rates in-place UPDATE on fact | Exchange rates applied in Gold load |
| `bIsProcessed` flag on raw staging | `FL_IS_PROCESSED` on Silver + `FL_IS_PROCESSED_TO_GOLD` on Silver→Gold |

### What's Preserved
- All ETL business logic from the 22 stored procedures
- Exchange rate hierarchy (Budget TY/NY/FY → Actual → BOE Spot → Override)
- Agent type handling (Net agents, CostPlus agents, special distributor IDs)
- Commission calculation logic (Tour Commissions + VAT Commissions)
- Package detection (Cluster/PackageTicket)
- WordPress date override for FTIX/ATIX bookings
- Fiscal year definition (November start)

---

## Migration Steps

### 1. Setup Fabric Workspace
- Create 1× Lakehouse: `AWG_BRONZE`
- Create 2× Warehouses: `AWG_SILVER`, `AWG_GOLD`

### 2. Deploy Tables (in order)
```
silver/tables/01 → 10   (in sequence)
gold/tables/01 → 07     (in sequence)
```

### 3. Seed Reference Data
```sql
-- Run the INSERT in:
silver/tables/10_L0_REF_INVOICE_STATUS.sql
-- Run the date dim population in:
gold/tables/01_L1_DIM_DATE.sql
```

### 4. Deploy Stored Procedures
```
silver/procedures/01 → 06
gold/procedures/01 → 03
```

### 5. Configure Bronze Ingestion
- Set up shortcut to Prio CSV files (S3/SFTP)
- Deploy notebook `NB_BRONZE_LOAD_PRIO_CSV`
- Configure SharePoint connectors (MD_LIST_*)
- Configure MySQL shortcuts (WP_FTIX, WP_ATIX)
- Configure BOE API pipeline

### 6. Historical Load
```sql
-- Migrate historical data from old DimSupplier, DimProduct, DimAgent, DimBooking, FactPrioSales
-- See orchestration/pipeline_execution_order.md for details
EXEC usp_L1_OrchestratePrioLoad @bReload = 1
```

### 7. Deploy Gold View
```
gold/views/01_PL_V_SALES.sql
```

### 8. Connect Power BI
Point existing reports at `PL_V_SALES` in the Gold Warehouse.
Column names have been preserved where possible (with the CD_/T_/AMT_/etc. semantic prefixes).

---

## Deprecated Objects (Not Migrated)

Over 80 tables were identified as deprecated — backups, test tables, superseded staging:
See `00_analysis/deprecated_objects.md` for the complete list.

These can be safely dropped from the old `PrioDW` database once the new pipeline is validated.
