# Active Objects in PrioDW (Old DWH)

This document identifies all tables, views, and stored procedures that are actively referenced
in stored procedures and production views. These objects must be migrated or replaced.

---

## CORE ETL PIPELINE

The main orchestration procedure is `usp_ProcessPrioBookings`, which calls:
1. `usp_ProcessGeneralDimensions` → upserts DimSupplier, DimProduct, DimAgent
2. `usp_ProcessBookings` → upserts DimBooking
3. `usp_ProcessPrioTransactions` → inserts/updates FactPrioSales
4. `usp_ProcessAgentCommissions` → adds commission lines to FactPrioSales
5. `usp_ProcessPrioPackages` → marks package lines
6. `usp_ProcessSupplierAccruals` → updates supplier recognition dates
7. `usp_ProcessExchangeRates` → applies exchange rates to FactPrioSales
8. `usp_ProcessDebtorsBalance` → updates DimBooking.DebtorBalance

---

## ACTIVE TABLES

### Staging / Raw (Bronze equivalent in old system)
| Old Table | New Bronze Table | Notes |
|-----------|-----------------|-------|
| `import_prio_transaction_staging_v2` | `PRIO_CSV_SALES_TRANSACTION` | Core Prio CSV staging. De-duped via `vimport_prio_transaction_staging` view (rank by last_modified_at + version). `bIsProcessed` flag marks what has been loaded |
| `import_prio_order_staging` | `PRIO_API_ORDERS` | Order details: LeadPaxName, email. Used by usp_ProcessBookings |
| `import_ftixv2_transaction` | `WP_FTIX_TRANSACTIONS` | FTIX WordPress transactions. Used by usp_ProcessBookings (date override) |
| `import_ftixv2_orders` | part of `WP_FTIX_TRANSACTIONS` | FTIX orders |
| `import_ftixv2_cc` | part of `WP_FTIX_TRANSACTIONS` | FTIX call centre booking attribution |
| `import_ftixv2_woo_pre_values` | part of `WP_FTIX_TRANSACTIONS` | FTIX WooCommerce pre-values |
| `import_atixv2_transaction` | `WP_ATIX_TRANSACTIONS` | ATIX WordPress transactions |
| `import_atixv2_orders` | part of `WP_ATIX_TRANSACTIONS` | ATIX orders |
| `import_atixv2_cc` | part of `WP_ATIX_TRANSACTIONS` | ATIX call centre booking attribution |
| `import_atixv2_woo_pre_values` | part of `WP_ATIX_TRANSACTIONS` | ATIX WooCommerce pre-values |
| `import_openpass_bookings` | `OPENPASS_BOOKINGS` | OpenPass bookings (currently limited use) |

### Reference / Lookup (maintained manually / from SharePoint)
| Old Table | New Silver Table | Notes |
|-----------|-----------------|-------|
| `DimInvoiceStatus` | `L0_REF_INVOICE_STATUS` | Maps invoice status string to invoice type + debit/credit |
| `DimInvoiceTypes` | `L0_REF_INVOICE_TYPES` | Invoice type metadata |
| `HaysOverrideCommissions` | `L0_REF_AGENT_COMMISSION_OVERRIDE` | Manual commission override for Hays agents |
| `AWTargets` | `L0_REF_TARGETS` | Weekly business targets (maintained manually) |
| `AgentChannels` | Part of `L0_SRG_CHANNEL` | Channel mappings for agents |
| `AgentGroups` | Part of `L0_SRG_AGENT` | Agent groupings |
| `AgentCharges` | `L0_REF_AGENT_CHARGES` | Agent charge schedules |
| `AgentPayments` | `L0_REF_AGENT_PAYMENTS` | Agent payment records |
| `SupplierPayments` | `L0_REF_SUPPLIER_PAYMENTS` | Supplier payment records |
| `DimFXContracts` | `L0_REF_FX_CONTRACTS` | FX rate contracts |
| `PrioSettings` | `L0_REF_PRIO_SETTINGS` | System settings |
| `import_finance_master_agent_invoices` | `L0_REF_AGENT_INVOICES` | Finance agent invoice master |
| `DebtorsPartialPayments` | `L0_REF_DEBTORS_PARTIAL_PAYMENTS` | Current debtor partial payment records |
| `DebtorsPartialPaymentsV2` | `L0_REF_DEBTORS_PARTIAL_PAYMENTS` | (same target) |
| `DebtorsPartialPaymentsV3` | `L0_REF_DEBTORS_PARTIAL_PAYMENTS` | (same target) |

### Dimension Tables (Silver equivalent in old system)
| Old Table | New Silver Table | Notes |
|-----------|-----------------|-------|
| `DimSupplier` | `L0_SRG_SUPPLIER` | Surrogate keys for suppliers from Prio source |
| `DimProduct` | `L0_SRG_PRODUCT` | Surrogate keys for products from Prio source |
| `DimAgent` | `L0_SRG_AGENT` | Surrogate keys for agents/distributors |
| `DimBooking` | `L0_SRG_BOOKING` | Surrogate keys for bookings (Order_ID + Product_ID) |

### Fact Tables (Gold equivalent in old system)
| Old Table | New Gold Table | Notes |
|-----------|---------------|-------|
| `FactPrioSales` | `L1_FACT_SALES_TRANSACTION` | Main fact (Prio source) |
| `FactOPSales` | `L1_FACT_SALES_TRANSACTION` | OpenPass source (merged into same fact) |
| `FactDebtorsPayments` | `L1_FACT_DEBTORS_PAYMENTS` | Debtor payment fact |

---

## ACTIVE VIEWS (Production)

| Old View | Notes |
|----------|-------|
| `vFactSales` | Main composite fact view (Prio + Traveller + OpenPass + HaysOverride) → becomes `PL_V_SALES` |
| `vDimBookings` | Combined booking dimension view → becomes part of gold layer |
| `vDimProducts` | Combined product dim view |
| `vDimAgents` | Combined agent dim view |
| `vDimSuppliers` (implied) | Supplier dim view |
| `vimport_prio_transaction_staging` | De-duplication view on staging → replaces with Silver SP logic |
| `vimport_prio_transaction_staging_v1` | Old version (for reference only) |

---

## ACTIVE STORED PROCEDURES

| Procedure | Status | New Equivalent |
|-----------|--------|---------------|
| `usp_ProcessPrioBookings` | ACTIVE - main orchestrator | `PL_SP_ProcessPrioSales` (pipeline SP) |
| `usp_ProcessGeneralDimensions` | ACTIVE | `usp_L0_MergeSuppliers`, `usp_L0_MergeProducts`, `usp_L0_MergeAgents` |
| `usp_ProcessBookings` | ACTIVE | `usp_L0_MergeBookings` |
| `usp_ProcessPrioTransactions` | ACTIVE | `usp_L0_MergeSalesTransactions` + `usp_L1_LoadFactSales` |
| `usp_ProcessAgentCommissions` | ACTIVE | `usp_L1_LoadAgentCommissions` |
| `usp_ProcessPrioPackages` | ACTIVE | Part of `usp_L1_LoadFactSales` |
| `usp_ProcessSupplierAccruals` | ACTIVE | `usp_L1_LoadSupplierAccruals` |
| `usp_ProcessExchangeRates` | ACTIVE | `usp_L1_LoadExchangeRates` |
| `usp_ProcessDebtorsBalance` | ACTIVE | `usp_L1_LoadDebtorsBalance` |
| `usp_ProcessOpenPassBookingsPayments` | ACTIVE | `usp_L0_LoadOpenPassPayments` |
| `usp_ProcessOpenPassBookingsReservations` | ACTIVE | `usp_L0_LoadOpenPassReservations` |
| `usp_ProcessOPBookingCancellation` | ACTIVE | Part of OpenPass pipeline |
| `usp_ProcessAgentRemits` | ACTIVE | `usp_L0_LoadAgentRemits` |
| `usp_ProcessDebtorsBalance` | ACTIVE | `usp_L1_LoadDebtorsBalance` |
| `usp_RemoveDuplicates_AtixV2Import` | ACTIVE | Part of Bronze notebook / pre-processing |
| `usp_RemoveDuplicates_FtixV2Import` | ACTIVE | Part of Bronze notebook / pre-processing |
| `usp_emarsys_cache` | ACTIVE - cache refresh | `usp_L1_RefreshEmarsysCache` |
| `usp_CalculateDailyWebsiteStats` | ACTIVE - analytics | `usp_L1_CalcDailyWebStats` |
| `usp_CopyAtixToTraveller` | ACTIVE | `usp_L0_SyncAtixToTraveller` |
| `usp_BookingsByDepartureMonth` | ACTIVE - reporting | `usp_L1_BookingsByDepartureMonth` |
| `usp_ProcessPrioInvoices` | COMMENTED OUT (disabled) | Skip for now |
| `usp_ProcessPrioTransactions_bck20250220` | BACKUP - DO NOT MIGRATE | Deprecated |
| `usp_QueryToHTMLTable` | UTILITY - not needed in Fabric | Skip |
