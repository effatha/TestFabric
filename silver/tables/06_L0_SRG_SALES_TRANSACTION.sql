/*
================================================================================
 Table: L0_SRG_SALES_TRANSACTION
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION
 Old equivalent: FactPrioSales (pre-Gold, before exchange rate calculation)
================================================================================
 Purpose:
   Surrogation and normalisation of individual sales transaction lines.
   Each row represents one invoice line (Revenue, Discount, Refund, Commission, etc.)
   for a booking+product combination.
   Exchange rates are applied in the Gold load (L1_FACT_SALES_TRANSACTION).
   This table tracks what has been loaded and allows idempotent reprocessing.
================================================================================
 Key: ID_SALES_TRANSACTION (surrogate)
 Business Key: CD_TRANSACTION_ID + CD_INVOICE_TYPE + CD_SOURCE
================================================================================
*/

CREATE TABLE [L0_SRG_SALES_TRANSACTION] (

    -- Surrogate key
    [ID_SALES_TRANSACTION]       BIGINT          NOT NULL,   -- Surrogate PK

    -- Business / natural key
    [CD_TRANSACTION_ID]          NVARCHAR(255)   NULL,       -- Source transaction ID (0 for virtual lines)
    [CD_INVOICE_TYPE]            NVARCHAR(50)    NULL,       -- 'Revenue', 'Discounts', 'Refunds', 'Tour Commissions', 'VAT Commissions'
    [CD_SOURCE]                  NVARCHAR(50)    NOT NULL DEFAULT 'PRIO',

    -- FK to surrogation tables (Silver)
    [ID_BOOKING]                 INT             NULL,       -- FK → L0_SRG_BOOKING.ID_BOOKING
    [ID_PRODUCT]                 INT             NULL,       -- FK → L0_SRG_PRODUCT.ID_PRODUCT
    [ID_SUPPLIER]                INT             NULL,       -- FK → L0_SRG_SUPPLIER.ID_SUPPLIER
    [ID_AGENT]                   INT             NULL,       -- FK → L0_SRG_AGENT.ID_AGENT

    -- Invoice metadata
    [CD_INVOICE_TID]             INT             NULL,       -- Invoice type ID (from old DimInvoiceTypes)
    [CD_INVOICE_SID]             INT             NULL,       -- Invoice status ID
    [CD_INVOICE_CATEGORY]        INT             NULL,       -- 2=Prio Retail, 4=Prio Agent
    [T_TYPE_AMOUNT]              NCHAR(1)        NULL,       -- 'D'=Debit (positive), 'C'=Credit (negative)
    [CD_ORDER_STATUS]            NVARCHAR(50)    NULL,       -- Invoice_Status from source

    -- Amounts (in transaction currency, before exchange rate)
    [AMT_REVENUE]                DECIMAL(19,4)   NULL,       -- Sale price (absolute)
    [AMT_SUPPLIER_PRICE]         DECIMAL(19,4)   NULL,       -- Supplier/buy rate price
    [AMT_COMMISSION]             DECIMAL(19,4)   NULL,       -- Distributor commission
    [AMT_REVENUE_VAT]            DECIMAL(19,4)   NULL,       -- VAT component of revenue (General_Tax)

    -- Currencies
    [CD_SALES_CURRENCY]          NVARCHAR(10)    NULL,       -- Sales / billing currency
    [CD_SUPPLIER_CURRENCY]       NVARCHAR(10)    NULL,       -- Supplier / cost currency

    -- Ticket details
    [T_TICKET_TYPE]              NVARCHAR(150)   NULL,       -- Pax type: Adult, Child, etc.
    [NUM_QUANTITY]               INT             NULL,       -- Number of tickets
    [CD_TICKET_NUMBER]           NVARCHAR(255)   NULL,       -- Pass/ticket reference number
    [T_MERCHANT_NAME]            NVARCHAR(255)   NULL,       -- Marketplace (Adyen) merchant name
    [T_SUPPLIER_ADMIN]           NVARCHAR(255)   NULL,       -- Actual supplier (from Flag_Name='Actual Supplier')

    -- Payment
    [T_PAYMENT_METHOD]           NVARCHAR(150)   NULL,       -- Payment method (ppcp→Paypal, etc.)
    [CD_INVOICE_REFERENCE]       NVARCHAR(150)   NULL,       -- PSP reference / payment reference

    -- Versioning
    [VL_VERSION]                 FLOAT           NULL,       -- Transaction_Version

    -- Dates
    [DT_ORDER]                   DATETIME2(0)    NULL,       -- Transaction datetime (Date+Time from CSV)

    -- Audit
    [FL_IS_PROCESSED_TO_GOLD]    BIT             NOT NULL DEFAULT 0,  -- Set to 1 once loaded to L1_FACT
    [DT_INSERT]                  DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]            DATETIME2(0)    NULL,

    CONSTRAINT [PK_L0_SRG_SALES_TRANSACTION] PRIMARY KEY CLUSTERED ([ID_SALES_TRANSACTION] ASC)
);

CREATE INDEX [IX_L0_SRG_SALES_TX_BOOKING]
    ON [L0_SRG_SALES_TRANSACTION] ([ID_BOOKING] ASC)
    INCLUDE ([CD_INVOICE_TYPE], [AMT_REVENUE], [CD_SALES_CURRENCY]);

CREATE INDEX [IX_L0_SRG_SALES_TX_PROCESSED]
    ON [L0_SRG_SALES_TRANSACTION] ([FL_IS_PROCESSED_TO_GOLD] ASC)
    INCLUDE ([ID_BOOKING], [ID_PRODUCT], [ID_AGENT]);
