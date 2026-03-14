/*
================================================================================
 Table: L0_SRG_SALES_TRANSACTION
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION
================================================================================
 Granularity: ONE ROW per CD_TRANSACTION_ID + CD_SOURCE
              (same grain as L0_PRIO_SALES_TRANSACTION — one ticket line)

 Design:
   All monetary amounts stored as ABSOLUTE values from source.
   FL_IS_REFUND = 1 for refund / cancellation transactions.
   Signs are applied in the Gold load (L1_FACT_SALES_TRANSACTION).
   Net agent and CostPlus agent revenue adjustments are applied here
   before Gold picks up the row.

 Agent commission columns:
   AMT_NET_DISTRIBUTOR_FEE  — net commission owed to agent (what we pay)
   AMT_DISTRIBUTOR_TAX      — VAT charged on that commission
   For distributors 49404/4365: AMT_NET_DISTRIBUTOR_FEE includes reseller fee
   For distributor 48749 (staff): AMT_NET_DISTRIBUTOR_FEE = 0
================================================================================
*/

CREATE TABLE [L0_SRG_SALES_TRANSACTION] (

    -- Surrogate key
    [ID_SALES_TRANSACTION]       BIGINT          NOT NULL,

    -- Business key (one row per transaction line)
    [CD_TRANSACTION_ID]          NVARCHAR(255)   NOT NULL,
    [CD_SOURCE]                  NVARCHAR(50)    NOT NULL DEFAULT 'PRIO',

    -- FK to surrogation tables
    [ID_BOOKING]                 INT             NULL,   -- FK → L0_SRG_BOOKING
    [ID_PRODUCT]                 INT             NULL,   -- FK → L0_SRG_PRODUCT (0 for discount lines)
    [ID_SUPPLIER]                INT             NULL,   -- FK → L0_SRG_SUPPLIER (0 for reprice/discount)
    [ID_AGENT]                   INT             NULL,   -- FK → L0_SRG_AGENT

    -- Order / invoice status
    [CD_ORDER_STATUS]            NVARCHAR(50)    NULL,   -- 'Confirmed', 'Refunded', 'Rebooked'
    [FL_IS_REFUND]               BIT             NOT NULL DEFAULT 0,  -- 1 = refund / cancellation row

    -- Sales amounts (absolute values — sign applied in Gold)
    [AMT_SALE_PRICE]             DECIMAL(19,4)   NULL,   -- Actual sale price
    [AMT_NET_SALE_PRICE]         DECIMAL(19,4)   NULL,   -- Net sale price (after distributor discount)
    [AMT_LIST_PRICE]             DECIMAL(19,4)   NULL,   -- Gross rack / list price
    [AMT_DISTRIBUTOR_DISCOUNT]   DECIMAL(19,4)   NULL,   -- Discount applied to distributor
    [AMT_GENERAL_TAX]            DECIMAL(19,4)   NULL,   -- VAT on sale (General_Tax)

    -- Supplier / cost amounts (absolute values)
    [AMT_SUPPLIER_PRICE]         DECIMAL(19,4)   NULL,   -- Gross supplier / buy price (Local_Currency_Price)
    [AMT_NET_SUPPLIER_PRICE]     DECIMAL(19,4)   NULL,   -- Net supplier price (Local_Currency_Net_Price)

    -- Agent commission amounts (absolute values)
    [AMT_DISTRIBUTOR_FEE]        DECIMAL(19,4)   NULL,   -- Gross distributor fee (list commission)
    [AMT_NET_DISTRIBUTOR_FEE]    DECIMAL(19,4)   NULL,   -- Net agent commission (what we owe)
    [AMT_DISTRIBUTOR_TAX]        DECIMAL(19,4)   NULL,   -- VAT charged on agent commission

    -- Other fees (absolute values)
    [AMT_RESELLER_FEE]           DECIMAL(19,4)   NULL,   -- Reseller / sub-agent fee
    [AMT_MERCHANT_FEE]           DECIMAL(19,4)   NULL,   -- Marketplace / Adyen merchant fee
    [AMT_AFFILIATE_FEE]          DECIMAL(19,4)   NULL,   -- Affiliate fee

    -- Currencies
    [CD_SALES_CURRENCY]          NVARCHAR(10)    NULL,   -- Sales / billing currency
    [CD_SUPPLIER_CURRENCY]       NVARCHAR(10)    NULL,   -- Supplier / cost currency

    -- Ticket details
    [T_TICKET_TYPE]              NVARCHAR(150)   NULL,   -- 'Adult', 'Child', etc.
    [NUM_QUANTITY]               INT             NULL,   -- Number of tickets (absolute)
    [CD_TICKET_NUMBER]           NVARCHAR(255)   NULL,   -- Pass / ticket reference
    [T_MERCHANT_NAME]            NVARCHAR(255)   NULL,   -- Marketplace (Adyen) merchant name
    [T_SUPPLIER_ADMIN]           NVARCHAR(255)   NULL,   -- Actual supplier (from Flag_Name='Actual Supplier')

    -- Payment
    [T_PAYMENT_METHOD]           NVARCHAR(150)   NULL,
    [CD_INVOICE_REFERENCE]       NVARCHAR(150)   NULL,   -- PSP / payment reference

    -- Versioning
    [VL_VERSION]                 FLOAT           NULL,
    [DT_ORDER]                   DATETIME2(0)    NULL,   -- Transaction datetime

    -- Audit
    [FL_IS_PROCESSED_TO_GOLD]    BIT             NOT NULL DEFAULT 0,
    [DT_INSERT]                  DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]            DATETIME2(0)    NULL,

    CONSTRAINT [PK_L0_SRG_SALES_TRANSACTION] PRIMARY KEY CLUSTERED ([ID_SALES_TRANSACTION] ASC),
    CONSTRAINT [UQ_L0_SRG_SALES_TX_BK] UNIQUE ([CD_TRANSACTION_ID], [CD_SOURCE])
);

CREATE INDEX [IX_L0_SRG_SALES_TX_BOOKING]
    ON [L0_SRG_SALES_TRANSACTION] ([ID_BOOKING] ASC)
    INCLUDE ([AMT_SALE_PRICE], [CD_SALES_CURRENCY], [FL_IS_REFUND]);

CREATE INDEX [IX_L0_SRG_SALES_TX_PROCESSED]
    ON [L0_SRG_SALES_TRANSACTION] ([FL_IS_PROCESSED_TO_GOLD] ASC)
    INCLUDE ([ID_BOOKING], [ID_PRODUCT], [ID_AGENT]);
