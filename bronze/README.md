# Bronze Layer - Microsoft Fabric Lakehouse

## Overview
The Bronze layer is a **Microsoft Fabric Lakehouse** storing raw data as **Delta tables**.
No SQL DDL is required here — tables are created by ingestion pipelines (notebooks, shortcuts, data flows).

---

## Bronze Tables by Source

### 1. PRIO_CSV_SALES_TRANSACTION
**Source:** Prio Ticket API — CSV transaction export
**Old equivalent:** `import_prio_transaction_staging_v2`
**Ingestion:** Fabric Data Pipeline → Notebook (required due to special characters & encoding in CSV)
**Type:** Incremental (new files appended, deduplicated in Silver)
**Key fields (mapped from CSV column headers):**

| CSV Column | Type | Notes |
|-----------|------|-------|
| Transaction_ID | string | Unique transaction identifier |
| Order_ID | string | Order / booking ID |
| Date | string | Transaction date |
| Time | string | Transaction time |
| Creation_Date | string | Order creation date |
| Creation_Time | string | Order creation time |
| Reseller_ID | string | Reseller identifier |
| Reseller_Name | string | Reseller name |
| Supplier_ID | string | Supplier identifier |
| Supplier_Name | string | Supplier name |
| Distributor_ID | string | Agent/distributor ID |
| Distributor_Name | string | Agent/distributor name |
| Channel_Type | string | Sales channel type |
| Channel_Name | string | Sales channel name |
| Product_ID | string | Product identifier |
| Product_Type_Title | string | Product name/title |
| Product_Type | string | Ticket type (Adult/Child/etc) |
| Pcs | string | Number of pieces |
| Pax | string | Number of passengers |
| Sales_Currency | string | Sales currency code |
| List_Price | string | List price |
| Sale_Price | string | Actual sale price |
| Net_Sale_Price | string | Net sale price |
| Distributor_Discount | string | Distributor discount amount |
| General_Tax | string | VAT/General tax |
| Supplier_Price | string | Gross supplier price |
| Net_Supplier_Price | string | Net supplier price |
| Supplier_Tax | string | Supplier tax |
| Market_Merchant_Name | string | Merchant/marketplace name |
| Market_Merchant_Fee | string | Merchant fee |
| Net_Market_Merchant_Fee | string | Net merchant fee |
| Reseller_Fee | string | Reseller commission |
| Net_Reseller_Fee | string | Net reseller commission |
| Distributor_Fee | string | Distributor commission |
| Net_Distributor_Fee | string | Net distributor commission |
| Distributor_Tax | string | Distributor tax/VAT |
| Affiliate_Fee | string | Affiliate commission |
| Net_Affiliate_Fee | string | Net affiliate commission |
| Retail_Payment_Method | string | Payment method |
| Status | string | Legacy status field |
| Combi_Type | string | Package type (Cluster/Single) |
| Statement_Type | string | Statement category |
| PSP_Reference | string | Adyen payment reference |
| Reservation_Date | string | Departure/reservation date |
| Pass_No. | string | Pass/ticket number |
| Currency | string | Supplier/local currency |
| Local_Currency_Price | string | Price in local/supplier currency |
| Ticket_Type_ID | string | Ticket type ID |
| Channel_ID | string | Channel ID |
| Client_Reference_No. | string | Customer reference number |
| Guest_Name | string | Guest name |
| Invoice_Status | string | Confirmed / Refunded / etc |
| Verification_Date | string | Verification date |
| Transaction_Version | string | Version number for updates |
| Flag_Name | string | Additional metadata key |
| Flag_Value | string | Additional metadata value |
| last_modified_at | string | Timestamp of last modification |
| parent_account_id | string | Parent distributor account |
| Parent_account_name | string | Parent distributor name |
| client_type | string | Client type |

**Special handling required:**
- File has UTF-8 BOM or Latin-1 encoding → use Python notebook for ingestion
- All fields arrive as strings → casting done in Silver layer
- Incremental load: use `last_modified_at` + filename as watermark
- Deduplication key: `Transaction_ID` (keep latest by `last_modified_at` DESC, then `Transaction_Version` DESC)
- Exclude soft-deleted rows: `bIsReplaced = 0` and `ManuallyDeleted = 0`

---

### 2. PRIO_API_ORDERS
**Source:** Prio Ticket API — Order details
**Old equivalent:** `import_prio_order_staging`
**Ingestion:** Fabric Data Pipeline → REST API connector
**Type:** Incremental
**Purpose:** Provides `Partner_Name` (lead pax name) and `Partner_email` for bookings

---

### 3. BOE_API_EXCHANGE_RATES
**Source:** Bank of England API
**Old equivalent:** `[AWTasks].dbo.BOEExchangeRates`
**Ingestion:** Fabric Data Pipeline → REST API
**Type:** Daily incremental
**Purpose:** Spot exchange rates used for historical actual rates

---

### 4. MD_LIST_EXCHANGE_RATES
**Source:** SharePoint List — AW internal exchange rate settings
**Old equivalent:** `[AWTasks].dbo.ExchangeRates` (budget/actual rates)
**Ingestion:** Fabric Data Pipeline → SharePoint connector
**Type:** Full refresh
**Purpose:** Budget rates (TY/NY/FY) and actual override rates per currency period

---

### 5. MD_LIST_PRODUCTS
**Source:** SharePoint List — Product metadata managed by AW
**Old equivalent:** Manual columns in `DimProduct` (tAWProductCity, tAWProductRegion, etc.)
**Ingestion:** Fabric Data Pipeline → SharePoint connector
**Type:** Full refresh
**Purpose:** AW-curated product location, category, and admin name overrides

---

### 6. MD_LIST_AGENTS
**Source:** SharePoint List — Agent/distributor settings managed by AW
**Old equivalent:** Manual columns in `DimAgent` (bIsTradeAgent, bIsNetAgent, tChannel, tAgentGroupName, etc.)
**Ingestion:** Fabric Data Pipeline → SharePoint connector
**Type:** Full refresh
**Purpose:** Agent classification (Trade/Direct, Net/Gross, CostPlus), groupings, commissions

---

### 7. WP_FTIX_TRANSACTIONS
**Source:** FloridaTix WordPress MySQL database
**Old equivalent:** `import_ftixv2_transaction` + `import_ftixv2_orders` + `import_ftixv2_cc`
**Ingestion:** Fabric Data Pipeline → MySQL connector (shortcut)
**Type:** Incremental
**Purpose:** WordPress order created dates, payment provider, call centre attribution for FTIX bookings

---

### 8. WP_ATIX_TRANSACTIONS
**Source:** AttractionTix WordPress MySQL database
**Old equivalent:** `import_atixv2_transaction` + `import_atixv2_orders` + `import_atixv2_cc`
**Ingestion:** Fabric Data Pipeline → MySQL connector (shortcut)
**Type:** Incremental
**Purpose:** WordPress order created dates, payment provider, call centre attribution for ATIX bookings

---

### 9. LARAVEL_FTIX_TRANSACTIONS
**Source:** New FloridaTix Laravel website database
**Old equivalent:** N/A (new source)
**Ingestion:** TBD
**Type:** Incremental
**Status:** Planned — not yet in production

---

## Lakehouse Configuration Notes

- All tables stored as **Delta format** for ACID compliance and time-travel
- Partition strategy: partition by `YEAR(transaction_date)` for large tables
- Retention: 30-day history for time-travel
- Notebooks should write using `spark.write.format("delta").mode("append").save(...)` for incremental loads
- Use `DeltaTable.forPath(...).merge(...)` for upsert patterns where needed

---

## Ingestion Notebook: PRIO CSV Loading

**Location:** `Notebooks/Bronze/NB_BRONZE_LOAD_PRIO_CSV`
**Trigger:** Fabric Data Pipeline on new file arrival in shortcut folder
**Key logic:**
1. Read CSV with explicit encoding (`latin-1` or `utf-8-sig`)
2. Strip special characters from string columns
3. Add `file_name`, `insert_date` audit columns
4. Append to Delta table `PRIO_CSV_SALES_TRANSACTION`
5. Deduplication is handled in Silver SP, not here
