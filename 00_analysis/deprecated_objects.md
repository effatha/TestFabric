# Deprecated / Unused Objects in PrioDW (Old DWH)

These objects are NOT referenced in any active stored procedure or production view.
They should be excluded from the migration to the new Medallion architecture.

---

## BACKUP TABLES (suffix: _bck*, _bk, _bck date-stamped)
These are point-in-time backups created before major changes. Not needed in new system.

- `AWTargets_bck20250513`
- `AWTargets_bck20251113`
- `DimAgent_bck20241115`
- `DimBooking_bck20250319`
- `DimBooking_bck20250612`
- `DimBooking_bck20251121`
- `dimBooking_bck20260125`
- `DimProduct_bck20241018`
- `DimProduct_bck20241115`
- `DimSupplier_bck20241115`
- `FactPrioSales_bck20250319`
- `FactPrioSales_bck20250612`
- `FactPrioSales_bck20251121`
- `factPrioSales_bck20260125`
- `FactDebtorsPayments_bck20260310`
- `HaysOverrideCommissions_bck20250310`
- `DebtorsPartialPayments_20240112`
- `DebtorsPartialPayments_bck20250207`
- `DebtorsPartialPayments_bck20250310`
- `DebtorsPartialPayments_bck20250513`
- `DebtorsPartialPayments_bck20250608`
- `DebtorsPartialPayments_bck20250709`
- `DebtorsPartialPayments_bck20250804`
- `DebtorsPartialPayments_bck20251013`
- `DebtorsPartialPayments_bck20251116`
- `DebtorsPartialPayments_bck20251208`
- `import_prio_daily_transactions_bk`
- `import_prio_order_staging_bk`
- `import_prio_transaction_staging_v2_bck20241125`
- `import_prio_transaction_staging_v2_sep_sync`
- `import_prio_transaction_staging_v2_YTD_April24`
- `import_prio_comercial_csv_bck`
- `import_prio_comercial_csv_bck20241127`
- `import_price_list_bck20241127`
- `import_ftixv2_orders_old`
- `import_ftixv2_transaction_old`

---

## DEV / TEST TABLES
- `DimBooking_DEV`
- `import_prio_products_region_test`
- `PrioTestBookings`

---

## SUPERSEDED STAGING TABLES (replaced by v2)
- `import_prio_transaction_staging` (replaced by `_staging_v2`)
- `import_prio_transaction_staging_all` (superseded)
- `import_prio_daily_transactions` (superseded by v2 flow)

---

## UNUSED IMPORT TABLES (no active SP reference)
- `import_prio_year_transactions`
- `import_prio_year_transactions_fy24`
- `import_prio_dashboard_order_csv`
- `import_prio_portal_transactions`
- `import_prio_recon_24_25` (reconciliation - one-off)
- `import_prio_ticket_destinations`
- `import_prio_comercial_csv` (commercial CSV - no active ETL)
- `import_google_analytics`
- `import_statements_init_hb`
- `import_prio_price_list`
- `import_prio_price_list_BCK`
- `import_prio_price_list_original`
- `import_price_list`
- `import_prio_invoices`
- `import_prio_invoices_all`
- `import_prio_order` (replaced by `import_prio_order_staging`)
- `import_atixv2_emails`
- `import_atixv2_notes`
- `import_atixv2_opt_in`
- `import_ftixv2_emails`
- `import_ftixv2_notes`
- `import_ftixv2_opt_in`
- `import_openpass_bookings_staging` (replaced by `import_openpass_bookings`)
- `AGED_CREDITORS`

---

## CACHE TABLES (replaced by Gold views in Fabric)
- `cache_vDimBookings`
- `cache_vDimProducts`
- `cache_vDimSuppliers`
- `cache_vFactSales`

---

## REFERENCE DATA WITH NO ACTIVE USE
- `Cities`
- `Country`
- `Regions`
- `PrioCatalogs`
- `TicketOffers`
- `ProductLocation`
- `MI_SUPPLIER_ATTRIBUTTES`
- `MissingBookingMatchingComments`
- `ImportExecutions` (task logging - replaced by Fabric monitoring)
- `PrioTransactionsRequests`
- `Numbers` (utility for date expansion - not needed in Fabric T-SQL)
- `Debtors` (superseded by DebtorsPartialPayments flow)
- `Debtors_V2` (superseded)
- `DimBooking_v2` (experimental - not in production)
- `DimProductPrices`
- `DimProductPriceVariation`
- `AcasReport` (one-off report table)
- `FactPrioSales_AgentPayments_test` (test table)
- `import_prio_transaction_staging_v2_YTD_April24`

---

## DEPRECATED VIEWS
- `vProductRegionTest` (test)
- `vDimProductsRegionTest` (test)
- `vDimBookings_test` (test)
- `vDimBookings_test20240410` (test)
- `vDimBookings_V2_test` (test)
- `vDimBookings_V2` (superseded by vDimBookings)
- `vDimBookings_AgentPayments` (agent payments test)
- `vFactSales_test` (test)
- `vFactSales_test_20240410` (test)
- `vFactSalesPrioDebtors_test` (test)
- `vAtixDailyOrdersByBooking_bk` (backup)
- `vFtixDailyOrdersByBooking_bk` (backup)
- `vOverallTargetsOld` (old version)
- `vimport_prio_transaction_staging_v1` (old version)
- `vPrioAllTransactions_ori` (original - superseded)
- `vDWHRec` (reconciliation - one-off)
- `vDWHRecCogs` (reconciliation - one-off)
- `vFactSalesPrioCOGS` (COGS - superseded by main fact view)
- `vFactSalesWithDF` (test view)

---

## DEPRECATED STORED PROCEDURES
- `usp_ProcessPrioTransactions_bck20250220` (backup copy)
- `usp_QueryToHTMLTable` (HTML email utility - not needed in Fabric)

---

## PRICING SCHEMA TABLES (separate concern, evaluate separately)
These belong to a `[pricing]` schema and may be a separate workstream:
- `[pricing].[DimPriceCatalogs]`
- `[pricing].[DimProductCatalogs]`
- `[pricing].[DimProductSeasons]`
