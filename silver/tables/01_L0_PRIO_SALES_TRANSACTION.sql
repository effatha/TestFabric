/*
================================================================================
 Table: L0_PRIO_SALES_TRANSACTION
 Layer: Silver (L0)
 Source: BRONZE.PRIO_CSV_SALES_TRANSACTION
 Old equivalent: import_prio_transaction_staging_v2 (via vimport_prio_transaction_staging)
================================================================================
 Purpose:
   Cleansed and typed version of the Prio transaction CSV data.
   - Renames columns to standard semantic naming convention
   - Casts all fields from string to correct data types
   - Removes special characters and trims whitespace
   - Keeps only the latest version of each transaction (deduplication)
   - Tracks processing status via FL_IS_PROCESSED
   - Excludes soft-deleted and replaced records
================================================================================
 Key: CD_TRANSACTION_ID (unique transaction)
 Dedup logic: RANK() OVER (PARTITION BY CD_TRANSACTION_ID ORDER BY DT_LAST_MODIFIED DESC, CD_TRANSACTION_VERSION DESC)
================================================================================
 Author: AWG_DWH Migration
 Date: 2026-03-14
================================================================================
*/

CREATE TABLE [L0_PRIO_SALES_TRANSACTION] (

    -- Surrogate / Control
    [ID_L0_PRIO_SALES_TRANSACTION] BIGINT         NOT NULL,  -- PK, auto-increment handled by pipeline sequence
    [DT_INSERT]                    DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATE]               DATETIME2(0)   NULL,
    [FL_IS_PROCESSED]              BIT            NOT NULL DEFAULT 0,  -- 0=pending, 1=loaded to Silver surrogation/Gold

    -- Transaction identifiers
    [CD_TRANSACTION_ID]            NVARCHAR(255)  NOT NULL,  -- Source: Transaction_ID
    [CD_ORDER_ID]                  NVARCHAR(255)  NULL,      -- Source: Order_ID (booking reference)
    [CD_TRANSACTION_VERSION]       NVARCHAR(50)   NULL,      -- Source: Transaction_Version
    [CD_PASS_NO]                   NVARCHAR(255)  NULL,      -- Source: Pass_No.
    [CD_CLIENT_REFERENCE_NO]       NVARCHAR(255)  NULL,      -- Source: Client_Reference_No.
    [CD_PSP_REFERENCE]             NVARCHAR(255)  NULL,      -- Source: PSP_Reference (Adyen)
    [CD_TICKET_TYPE_ID]            NVARCHAR(255)  NULL,      -- Source: Ticket_Type_ID
    [CD_CHANNEL_ID]                NVARCHAR(255)  NULL,      -- Source: Channel_ID

    -- Dates & times (cast from string)
    [DT_TRANSACTION]               DATETIME2(0)   NULL,      -- Source: Date + Time (transaction datetime)
    [DT_CREATED]                   DATETIME2(0)   NULL,      -- Source: Creation_Date + Creation_Time (order creation)
    [DT_RESERVATION]               DATE           NULL,      -- Source: Reservation_Date (departure date)
    [DT_VERIFICATION]              DATE           NULL,      -- Source: Verification_Date
    [DT_LAST_MODIFIED]             DATETIME2(0)   NULL,      -- Source: last_modified_at

    -- Reseller
    [CD_RESELLER_ID]               NVARCHAR(255)  NULL,      -- Source: Reseller_ID
    [T_RESELLER_NAME]              NVARCHAR(500)  NULL,      -- Source: Reseller_Name

    -- Supplier
    [CD_SUPPLIER_ID]               INT            NULL,      -- Source: Supplier_ID (cast to INT)
    [T_SUPPLIER_NAME]              NVARCHAR(500)  NULL,      -- Source: Supplier_Name

    -- Distributor / Agent
    [CD_DISTRIBUTOR_ID]            INT            NULL,      -- Source: Distributor_ID (cast to INT)
    [T_DISTRIBUTOR_NAME]           NVARCHAR(500)  NULL,      -- Source: Distributor_Name
    [CD_PARENT_ACCOUNT_ID]         NVARCHAR(255)  NULL,      -- Source: parent_account_id
    [T_PARENT_ACCOUNT_NAME]        NVARCHAR(500)  NULL,      -- Source: Parent_account_name
    [T_CLIENT_TYPE]                NVARCHAR(255)  NULL,      -- Source: client_type
    [T_VAT_NO]                     NVARCHAR(255)  NULL,      -- Source: vat_no

    -- Channel
    [CD_CHANNEL_TYPE]              NVARCHAR(255)  NULL,      -- Source: Channel_Type
    [T_CHANNEL_NAME]               NVARCHAR(255)  NULL,      -- Source: Channel_Name
    [T_SALEDESK_NAME]              NVARCHAR(255)  NULL,      -- Source: Saledesk_Name

    -- Product
    [CD_PRODUCT_ID]                INT            NULL,      -- Source: Product_ID (cast to INT)
    [T_PRODUCT_TYPE_TITLE]         NVARCHAR(500)  NULL,      -- Source: Product_Type_Title (product name)
    [T_PRODUCT_TYPE]               NVARCHAR(255)  NULL,      -- Source: Product_Type (ticket type: Adult/Child)
    [T_COMBI_TYPE]                 NVARCHAR(255)  NULL,      -- Source: Combi_Type (Single/Cluster for packages)
    [T_STATEMENT_TYPE]             NVARCHAR(255)  NULL,      -- Source: Statement_Type

    -- Quantities
    [NUM_PCS]                      INT            NULL,      -- Source: Pcs (number of tickets)
    [NUM_PAX]                      INT            NULL,      -- Source: Pax (number of passengers)

    -- Currencies
    [CD_SALES_CURRENCY]            NVARCHAR(10)   NULL,      -- Source: Sales_Currency
    [CD_SUPPLIER_CURRENCY]         NVARCHAR(10)   NULL,      -- Source: Currency (local/supplier currency)

    -- Sales amounts (sales currency)
    [AMT_LIST_PRICE]               DECIMAL(19,4)  NULL,      -- Source: List_Price
    [AMT_SALE_PRICE]               DECIMAL(19,4)  NULL,      -- Source: Sale_Price
    [AMT_NET_SALE_PRICE]           DECIMAL(19,4)  NULL,      -- Source: Net_Sale_Price
    [AMT_DISTRIBUTOR_DISCOUNT]     DECIMAL(19,4)  NULL,      -- Source: Distributor_Discount
    [AMT_GENERAL_TAX]              DECIMAL(19,4)  NULL,      -- Source: General_Tax (VAT)

    -- Supplier amounts (supplier currency)
    [AMT_SUPPLIER_PRICE]           DECIMAL(19,4)  NULL,      -- Source: Supplier_Price (gross)
    [AMT_NET_SUPPLIER_PRICE]       DECIMAL(19,4)  NULL,      -- Source: Net_Supplier_Price
    [AMT_SUPPLIER_TAX]             DECIMAL(19,4)  NULL,      -- Source: Supplier_Tax
    [AMT_LOCAL_CURRENCY_PRICE]     DECIMAL(19,4)  NULL,      -- Source: Local_Currency_Price (buy rate)
    [AMT_LOCAL_CURRENCY_NET_PRICE] DECIMAL(19,4)  NULL,      -- Source: Local_Currency_Net_Price

    -- Fee structures
    [T_MERCHANT_NAME]              NVARCHAR(255)  NULL,      -- Source: Market_Merchant_Name
    [AMT_MERCHANT_FEE]             DECIMAL(19,4)  NULL,      -- Source: Market_Merchant_Fee
    [AMT_NET_MERCHANT_FEE]         DECIMAL(19,4)  NULL,      -- Source: Net_Market_Merchant_Fee
    [AMT_MERCHANT_TAX]             DECIMAL(19,4)  NULL,      -- Source: Market_Merchant_Tax
    [AMT_RESELLER_FEE]             DECIMAL(19,4)  NULL,      -- Source: Reseller_Fee
    [AMT_NET_RESELLER_FEE]         DECIMAL(19,4)  NULL,      -- Source: Net_Reseller_Fee
    [AMT_RESELLER_TAX]             DECIMAL(19,4)  NULL,      -- Source: Reseller_Tax
    [AMT_DISTRIBUTOR_FEE]          DECIMAL(19,4)  NULL,      -- Source: Distributor_Fee
    [AMT_NET_DISTRIBUTOR_FEE]      DECIMAL(19,4)  NULL,      -- Source: Net_Distributor_Fee
    [AMT_DISTRIBUTOR_TAX]          DECIMAL(19,4)  NULL,      -- Source: Distributor_Tax
    [AMT_AFFILIATE_FEE]            DECIMAL(19,4)  NULL,      -- Source: Affiliate_Fee
    [AMT_NET_AFFILIATE_FEE]        DECIMAL(19,4)  NULL,      -- Source: Net_Affiliate_Fee
    [AMT_AFFILIATE_TAX]            DECIMAL(19,4)  NULL,      -- Source: Affiliate_Tax

    -- Status & metadata
    [CD_INVOICE_STATUS]            NVARCHAR(100)  NULL,      -- Source: Invoice_Status (Confirmed/Refunded/etc)
    [T_PAYMENT_METHOD]             NVARCHAR(255)  NULL,      -- Source: Retail_Payment_Method
    [T_GUEST_NAME]                 NVARCHAR(500)  NULL,      -- Source: Guest_Name
    [T_FLAG_NAME]                  NVARCHAR(255)  NULL,      -- Source: Flag_Name (additional metadata key)
    [T_FLAG_VALUE]                 NVARCHAR(500)  NULL,      -- Source: Flag_Value
    [T_FILE_NAME]                  NVARCHAR(500)  NULL,      -- Source: File_name (source file)
    [T_WDW_PAYMENT_OPTIONS]        NVARCHAR(500)  NULL,      -- Source: wdw_payment_options

    CONSTRAINT [PK_L0_PRIO_SALES_TRANSACTION] PRIMARY KEY CLUSTERED ([ID_L0_PRIO_SALES_TRANSACTION] ASC)
);

-- Index for ETL processing (find unprocessed rows)
CREATE INDEX [IX_L0_PRIO_SALES_TRANSACTION_FL_IS_PROCESSED]
    ON [L0_PRIO_SALES_TRANSACTION] ([FL_IS_PROCESSED] ASC)
    INCLUDE ([CD_TRANSACTION_ID], [CD_ORDER_ID], [CD_PRODUCT_ID], [CD_DISTRIBUTOR_ID], [CD_SUPPLIER_ID]);

-- Index for deduplication and version lookup
CREATE INDEX [IX_L0_PRIO_SALES_TRANSACTION_TRANSACTION_ID]
    ON [L0_PRIO_SALES_TRANSACTION] ([CD_TRANSACTION_ID] ASC)
    INCLUDE ([CD_TRANSACTION_VERSION], [DT_LAST_MODIFIED], [FL_IS_PROCESSED]);
