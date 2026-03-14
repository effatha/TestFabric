/*
================================================================================
 Table: L1_FACT_SALES_TRANSACTION
 Layer: Gold (L1)
 Source: L0_SRG_SALES_TRANSACTION, L0_SRG_BOOKING, L0_EXCHANGE_RATES
================================================================================
 Granularity: ONE ROW per CD_TRANSACTION_ID + CD_SOURCE
              (same grain as L0_PRIO_SALES_TRANSACTION — one ticket line per booking+product)

 Design:
   All monetary amounts stored as REAL SIGNED VALUES:
     - Confirmed transactions: positive
     - Refunded / cancelled:   negative
   No invoice type rows. No D/C classification. All measures on one row.

   TC  = Transaction / Sales currency (as billed)
   BC  = Base currency GBP (after exchange rate)

   Agent commission measures (explicit columns):
     AMT_AGENT_COMMISSION_*        = net commission owed to agent (AMT_NET_DISTRIBUTOR_FEE)
     AMT_VAT_ON_COMMISSION_*       = VAT charged on agent commission (AMT_DISTRIBUTOR_TAX)
     AMT_TOTAL_COMMISSION_COST_*   = agent commission + VAT on commission

   Exchange rate hierarchy (applied in load SP):
     Budget rate → Actual rate → BOE Spot rate → Override → Historical hardcode (2022 USD)
================================================================================
*/

CREATE TABLE [L1_FACT_SALES_TRANSACTION] (

    -- Surrogate PK
    [ID_FACT_SALES]                  BIGINT          NOT NULL,

    -- Natural key
    [CD_TRANSACTION_ID]              NVARCHAR(255)   NOT NULL,
    [CD_SOURCE_SYSTEM]               NVARCHAR(50)    NOT NULL DEFAULT 'PRIO',

    -- Booking / order context (grain: one ticket line within a booking+product)
    [CD_ORDER_ID]                    NVARCHAR(255)   NULL,
    [CD_PRODUCT_ID]                  INT             NULL,
    [ID_BOOKING]                     INT             NULL,   -- FK → L0_SRG_BOOKING

    -- Dimension foreign keys
    [ID_PRODUCT]                     INT             NULL,   -- FK → L1_DIM_PRODUCT
    [ID_SUPPLIER]                    INT             NULL,   -- FK → L1_DIM_SUPPLIER
    [ID_AGENT]                       INT             NULL,   -- FK → L1_DIM_AGENT
    [ID_RESELLER]                    INT             NULL,   -- FK → L1_DIM_RESELLER (optional)

    -- Order / invoice status
    [CD_ORDER_STATUS]                NVARCHAR(50)    NULL,   -- 'Confirmed', 'Refunded', 'Rebooked'
    [FL_IS_REFUND]                   BIT             NOT NULL DEFAULT 0,   -- 1 = refund row (amounts are negative)

    -- Dates
    [DT_TRANSACTION]                 DATETIME2(0)    NULL,   -- Transaction datetime
    [DT_CREATED]                     DATE            NULL,   -- Booking creation date
    [DT_DEPARTURE]                   DATE            NULL,   -- Visit / departure date
    [DT_CANCELLATION]                DATE            NULL,   -- Cancellation date (if any)

    -- Booking attributes (denormalized from L0_SRG_BOOKING)
    [T_BOOKING_TYPE]                 NVARCHAR(50)    NULL,   -- 'Trade', 'Direct'
    [T_BOOKING_SOURCE]               NVARCHAR(100)   NULL,   -- 'PrioTicket', 'FloridaTix', 'AttractionTix'
    [T_PACKAGE_TYPE]                 NVARCHAR(50)    NULL,   -- 'Single Ticket', 'Package', 'PackageTicket'
    [T_FISCAL_YEAR]                  NVARCHAR(20)    NULL,   -- e.g. 'FY2025/2026'
    [T_LEAD_PAX_NAME]                NVARCHAR(255)   NULL,
    [T_PAYMENT_METHOD]               NVARCHAR(150)   NULL,
    [CD_INVOICE_REFERENCE]           NVARCHAR(150)   NULL,   -- PSP / payment reference

    -- Ticket attributes
    [T_TICKET_TYPE]                  NVARCHAR(150)   NULL,   -- 'Adult', 'Child', etc.
    [T_PAX_TYPE]                     NVARCHAR(20)    NULL,   -- 'Adult', 'Child', 'Other'
    [NUM_TICKET_QUANTITY]            INT             NULL,   -- Signed: positive = sale, negative = refund
    [CD_TICKET_NUMBER]               NVARCHAR(255)   NULL,
    [T_MERCHANT_NAME]                NVARCHAR(255)   NULL,
    [T_SUPPLIER_ADMIN]               NVARCHAR(255)   NULL,
    [VL_VERSION]                     FLOAT           NULL,

    -- Currencies
    [CD_SALES_CURRENCY]              NVARCHAR(10)    NULL,
    [CD_SUPPLIER_CURRENCY]           NVARCHAR(10)    NULL,
    [CD_BASE_CURRENCY]               NVARCHAR(10)    NOT NULL DEFAULT 'GBP',

    -- Exchange rates
    [VL_SALES_EXCHANGE_RATE]         DECIMAL(19,6)   NULL,
    [VL_SUPPLIER_EXCHANGE_RATE]      DECIMAL(19,6)   NULL,
    [CD_EXCHANGE_RATE_TYPE]          NVARCHAR(50)    NULL,   -- 'Budget', 'Actual', 'BOE_Spot', 'Override', 'Historical_Hardcode'

    -- -------------------------------------------------------
    -- Sales amounts — Transaction Currency (TC)
    -- Signed: positive for confirmed, negative for refunds
    -- -------------------------------------------------------
    [AMT_SALE_PRICE_TC]              DECIMAL(19,4)   NULL,   -- Actual sale price charged
    [AMT_NET_SALE_PRICE_TC]          DECIMAL(19,4)   NULL,   -- Net of distributor discount
    [AMT_LIST_PRICE_TC]              DECIMAL(19,4)   NULL,   -- Gross rack / list price
    [AMT_DISTRIBUTOR_DISCOUNT_TC]    DECIMAL(19,4)   NULL,   -- Discount (negative or zero)
    [AMT_GENERAL_TAX_TC]             DECIMAL(19,4)   NULL,   -- VAT on sale

    -- -------------------------------------------------------
    -- Supplier / cost amounts — Supplier Currency (TC)
    -- -------------------------------------------------------
    [AMT_SUPPLIER_PRICE_TC]          DECIMAL(19,4)   NULL,   -- Gross supplier / buy price
    [AMT_NET_SUPPLIER_PRICE_TC]      DECIMAL(19,4)   NULL,   -- Net supplier price

    -- -------------------------------------------------------
    -- Fee structures — Transaction Currency (TC)
    -- -------------------------------------------------------
    [AMT_DISTRIBUTOR_FEE_TC]         DECIMAL(19,4)   NULL,   -- Gross agent commission (list)
    [AMT_NET_DISTRIBUTOR_FEE_TC]     DECIMAL(19,4)   NULL,   -- Net agent commission (what we owe)
    [AMT_DISTRIBUTOR_TAX_TC]         DECIMAL(19,4)   NULL,   -- VAT charged on agent commission
    [AMT_RESELLER_FEE_TC]            DECIMAL(19,4)   NULL,
    [AMT_MERCHANT_FEE_TC]            DECIMAL(19,4)   NULL,
    [AMT_AFFILIATE_FEE_TC]           DECIMAL(19,4)   NULL,

    -- -------------------------------------------------------
    -- Sales amounts — Base Currency GBP (BC)
    -- -------------------------------------------------------
    [AMT_SALE_PRICE_BC]              DECIMAL(19,4)   NULL,
    [AMT_NET_SALE_PRICE_BC]          DECIMAL(19,4)   NULL,
    [AMT_LIST_PRICE_BC]              DECIMAL(19,4)   NULL,
    [AMT_DISTRIBUTOR_DISCOUNT_BC]    DECIMAL(19,4)   NULL,
    [AMT_GENERAL_TAX_BC]             DECIMAL(19,4)   NULL,

    -- -------------------------------------------------------
    -- Supplier amounts — Base Currency GBP (BC)
    -- -------------------------------------------------------
    [AMT_SUPPLIER_PRICE_BC]          DECIMAL(19,4)   NULL,
    [AMT_NET_SUPPLIER_PRICE_BC]      DECIMAL(19,4)   NULL,

    -- -------------------------------------------------------
    -- Fee structures — Base Currency GBP (BC)
    -- -------------------------------------------------------
    [AMT_DISTRIBUTOR_FEE_BC]         DECIMAL(19,4)   NULL,
    [AMT_NET_DISTRIBUTOR_FEE_BC]     DECIMAL(19,4)   NULL,
    [AMT_DISTRIBUTOR_TAX_BC]         DECIMAL(19,4)   NULL,
    [AMT_RESELLER_FEE_BC]            DECIMAL(19,4)   NULL,
    [AMT_MERCHANT_FEE_BC]            DECIMAL(19,4)   NULL,
    [AMT_AFFILIATE_FEE_BC]           DECIMAL(19,4)   NULL,

    -- -------------------------------------------------------
    -- Computed commission measures — Base Currency GBP
    -- Signed: negative on refund rows
    -- -------------------------------------------------------
    -- Net commission owed to agent (= AMT_NET_DISTRIBUTOR_FEE_BC)
    -- For Net Agents: always 0 (deducted from revenue already)
    -- For CostPlus agents: always 0 (margin embedded in sale price)
    [AMT_AGENT_COMMISSION_BC]        DECIMAL(19,4)   NULL,

    -- VAT charged on the agent commission (= AMT_DISTRIBUTOR_TAX_BC)
    [AMT_VAT_ON_COMMISSION_BC]       DECIMAL(19,4)   NULL,

    -- Total commission cost (agent commission + VAT on commission)
    [AMT_TOTAL_COMMISSION_COST_BC]   DECIMAL(19,4)   NULL,

    -- -------------------------------------------------------
    -- Audit / control
    -- -------------------------------------------------------
    [DT_INSERT]                      DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]                DATETIME2(0)    NULL,

    CONSTRAINT [PK_L1_FACT_SALES_TRANSACTION] PRIMARY KEY CLUSTERED ([ID_FACT_SALES] ASC),
    CONSTRAINT [UQ_L1_FACT_TRANSACTION] UNIQUE ([CD_TRANSACTION_ID], [CD_SOURCE_SYSTEM])
);

-- Analytics indexes
CREATE INDEX [IX_L1_FACT_DT_DEPARTURE]
    ON [L1_FACT_SALES_TRANSACTION] ([DT_DEPARTURE] ASC)
    INCLUDE ([ID_PRODUCT], [ID_AGENT], [CD_ORDER_STATUS], [FL_IS_REFUND],
             [AMT_SALE_PRICE_BC], [AMT_NET_DISTRIBUTOR_FEE_BC]);

CREATE INDEX [IX_L1_FACT_DT_CREATED]
    ON [L1_FACT_SALES_TRANSACTION] ([DT_CREATED] ASC)
    INCLUDE ([CD_ORDER_ID], [ID_AGENT], [AMT_SALE_PRICE_BC], [FL_IS_REFUND]);

CREATE INDEX [IX_L1_FACT_ORDER]
    ON [L1_FACT_SALES_TRANSACTION] ([CD_ORDER_ID] ASC, [CD_PRODUCT_ID] ASC)
    INCLUDE ([CD_ORDER_STATUS], [FL_IS_REFUND], [AMT_SALE_PRICE_BC], [AMT_SUPPLIER_PRICE_BC]);
