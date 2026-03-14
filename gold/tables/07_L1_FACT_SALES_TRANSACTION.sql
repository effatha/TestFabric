/*
================================================================================
 Table: L1_FACT_SALES_TRANSACTION
 Layer: Gold (L1)
 Source: L0_SRG_SALES_TRANSACTION, L0_SRG_BOOKING, L0_EXCHANGE_RATES,
         L0_REF_AGENT_COMMISSION_OVERRIDE
 Old equivalent: FactPrioSales + FactOPSales + HaysOverrideCommissions
                 (exposed via vFactSales view)
================================================================================
 Purpose:
   Fully denormalized, analytics-ready fact table for sales transactions.
   One row per transaction invoice line.
   All monetary amounts stored in BOTH:
     - Transaction currency (TC) - as recorded
     - Base currency GBP (BC) - after exchange rate conversion
   Exchange rates applied:
     - Budget rate: for future departures (TY/NY/FY based on booking date vs departure year)
     - Actual rate: for past departures
     - BOE spot rate: fallback when no budget/actual exists
     - Override rates: for specific product/agent/date combinations
================================================================================
 Star Schema Foreign Keys:
   ID_PRODUCT  → L1_DIM_PRODUCT
   ID_SUPPLIER → L1_DIM_SUPPLIER
   ID_AGENT    → L1_DIM_AGENT
   Date columns (DT_DEPARTURE, DT_CREATED, DT_TRANSACTION) → L1_DIM_DATE on DT_DATE
================================================================================
 Author: AWG_DWH Migration
 Date: 2026-03-14
================================================================================
*/

CREATE TABLE [L1_FACT_SALES_TRANSACTION] (

    -- Surrogate PK
    [ID_FACT_SALES]             BIGINT         NOT NULL,

    -- Dimension foreign keys
    [ID_PRODUCT]                INT            NULL,   -- FK → L1_DIM_PRODUCT
    [ID_SUPPLIER]               INT            NULL,   -- FK → L1_DIM_SUPPLIER
    [ID_AGENT]                  INT            NULL,   -- FK → L1_DIM_AGENT
    [ID_CHANNEL]                INT            NULL,   -- FK → L1_DIM_CHANNEL (optional)

    -- Booking linkage (not a separate dimension in star schema - booking details denormalized)
    [CD_ORDER_ID]               NVARCHAR(255)  NULL,   -- Booking/order ID
    [CD_PRODUCT_ID]             INT            NULL,   -- Product ID within order
    [CD_SALES_TRANSACTION]      NVARCHAR(255)  NULL,   -- Unique transaction code

    -- Source / system identifiers
    [CD_SOURCE_SYSTEM]          NVARCHAR(50)   NULL DEFAULT 'PRIO',
    [CD_TRANSACTION_ID]         NVARCHAR(255)  NULL,
    [CD_TICKET_NUMBER]          NVARCHAR(255)  NULL,   -- Pass/ticket reference

    -- Invoice classification
    [T_INVOICE_TYPE]            NVARCHAR(50)   NULL,   -- 'Revenue', 'Refunds', 'Discounts', 'Tour Commissions', 'VAT Commissions'
    [CD_TYPE_AMOUNT]            NCHAR(1)       NULL,   -- 'D'=Debit, 'C'=Credit
    [CD_INVOICE_CATEGORY]       INT            NULL,   -- 2=Retail, 4=Agent
    [CD_INVOICE_TID]            INT            NULL,
    [CD_INVOICE_SID]            INT            NULL,
    [CD_SALES_STATUS]           NVARCHAR(50)   NULL,   -- 'Confirmed', 'Refunded'

    -- Dates
    [DT_TRANSACTION]            DATETIME2(0)   NULL,   -- Transaction date/time
    [DT_DEPARTURE]              DATE           NULL,   -- Departure/visit date
    [DT_CREATED]                DATE           NULL,   -- Booking creation date
    [DT_CANCELLATION]           DATE           NULL,   -- Cancellation date (if applicable)

    -- Booking attributes (denormalized from L0_SRG_BOOKING)
    [T_BOOKING_TYPE]            NVARCHAR(50)   NULL,   -- 'Trade', 'Direct'
    [T_BOOKING_SOURCE]          NVARCHAR(100)  NULL,   -- 'PrioTicket', 'Call Centre', 'FloridaTix', 'AttractionTix'
    [T_PACKAGE_TYPE]            NVARCHAR(50)   NULL,   -- 'Single Ticket', 'Package', 'PackageTicket'
    [T_LEAD_PAX_NAME]           NVARCHAR(255)  NULL,
    [T_FISCAL_YEAR]             NVARCHAR(20)   NULL,   -- 'FY2025/2026'
    [T_PAYMENT_METHOD]          NVARCHAR(150)  NULL,
    [CD_INVOICE_REFERENCE]      NVARCHAR(150)  NULL,   -- PSP / payment reference

    -- Ticket attributes
    [T_TICKET_TYPE]             NVARCHAR(150)  NULL,   -- 'Adult', 'Child', etc.
    [T_PAX_TYPE]                NVARCHAR(20)   NULL,   -- 'Adult', 'Child', 'Other'
    [NUM_TICKET_QUANTITY]       INT            NULL,
    [T_MERCHANT_NAME]           NVARCHAR(255)  NULL,   -- Adyen marketplace
    [T_SUPPLIER_ADMIN]          NVARCHAR(255)  NULL,   -- Actual supplier name

    -- Currency
    [CD_SALES_CURRENCY]         NVARCHAR(10)   NULL,   -- Transaction/sales currency
    [CD_SUPPLIER_CURRENCY]      NVARCHAR(10)   NULL,   -- Supplier/cost currency
    [CD_BASE_CURRENCY]          NVARCHAR(10)   NULL DEFAULT 'GBP',

    -- Exchange rates
    [VL_SALES_EXCHANGE_RATE]    DECIMAL(19,6)  NULL,   -- Sales currency → GBP
    [VL_SUPPLIER_EXCHANGE_RATE] DECIMAL(19,6)  NULL,   -- Supplier currency → GBP
    [CD_EXCHANGE_RATE_TYPE]     NVARCHAR(50)   NULL,   -- 'Budget', 'Actual', 'BOE_Spot', 'Override'

    -- Sales amounts (transaction currency)
    [AMT_GROSS_SALES_PRICE_TC]  DECIMAL(19,4)  NULL,   -- Gross sale price (list price)
    [AMT_NET_SALES_PRICE_TC]    DECIMAL(19,4)  NULL,   -- Net sale price
    [AMT_REVENUE_TC]            DECIMAL(19,4)  NULL,   -- Revenue amount (absolute)
    [AMT_DISCOUNT_TC]           DECIMAL(19,4)  NULL,   -- Discount amount
    [AMT_GENERAL_TAX_TC]        DECIMAL(19,4)  NULL,   -- VAT/tax component

    -- Sales amounts (base currency GBP)
    [AMT_GROSS_SALES_PRICE_BC]  DECIMAL(19,4)  NULL,
    [AMT_NET_SALES_PRICE_BC]    DECIMAL(19,4)  NULL,
    [AMT_REVENUE_BC]            DECIMAL(19,4)  NULL,
    [AMT_DISCOUNT_BC]           DECIMAL(19,4)  NULL,

    -- Supplier/cost amounts (supplier currency)
    [AMT_SUPPLIER_PRICE_TC]     DECIMAL(19,4)  NULL,   -- Supplier buy rate (local currency price)
    [AMT_NET_SUPPLIER_PRICE_TC] DECIMAL(19,4)  NULL,

    -- Supplier amounts (base currency GBP)
    [AMT_SUPPLIER_PRICE_BC]     DECIMAL(19,4)  NULL,
    [AMT_NET_SUPPLIER_PRICE_BC] DECIMAL(19,4)  NULL,

    -- Fee structures (transaction currency)
    [AMT_MERCHANT_FEE_TC]       DECIMAL(19,4)  NULL,
    [AMT_RESELLER_FEE_TC]       DECIMAL(19,4)  NULL,
    [AMT_DISTRIBUTOR_FEE_TC]    DECIMAL(19,4)  NULL,   -- Commission to agent
    [AMT_NET_DISTRIBUTOR_FEE_TC] DECIMAL(19,4) NULL,
    [AMT_AFFILIATE_FEE_TC]      DECIMAL(19,4)  NULL,

    -- P&L metrics (base currency GBP) - aligned to Instructions.md P&L structure
    [VL_NET_TICKET_ORDER_QTY]   INT            NULL,   -- Net quantity (sales - cancellations)
    [AMT_TURNOVER_GBP]          DECIMAL(19,4)  NULL,   -- Revenue without discounts/tax
    [AMT_DISCOUNTS_GBP]         DECIMAL(19,4)  NULL,   -- Total discounts applied
    [AMT_TAX_CHARGES_GBP]       DECIMAL(19,4)  NULL,   -- Tax charges
    [AMT_GROSS_ORDER_VALUE_GBP] DECIMAL(19,4)  NULL,   -- Turnover - Discounts - Tax
    [AMT_CANCELLED_VALUE_GBP]   DECIMAL(19,4)  NULL,   -- Cancelled order value
    [AMT_NET_ORDER_VALUE_GBP]   DECIMAL(19,4)  NULL,   -- Gross - Cancelled
    [AMT_AGENT_COMMISSIONS_GBP] DECIMAL(19,4)  NULL,   -- Agent commission costs
    [AMT_NET_PRODUCT_COSTS_GBP] DECIMAL(19,4)  NULL,   -- COGS (supplier costs)
    [AMT_GROSS_MARGIN_GBP]      DECIMAL(19,4)  NULL,   -- NOV - Commissions - COGS
    [AMT_MARKETING_COSTS_GBP]   DECIMAL(19,4)  NULL,   -- Marketing attribution
    [AMT_OTHER_COSTS_GBP]       DECIMAL(19,4)  NULL,
    [AMT_NET_MARGIN_GBP]        DECIMAL(19,4)  NULL,   -- Gross Margin - Marketing - Other

    -- Supplier recognition / accrual
    [DT_SUPPLIER_RECOGNITION]   DATE           NULL,   -- Date supplier cost is recognised
    [FL_IS_ACCRUAL]             BIT            NULL DEFAULT 0,

    -- Version / audit
    [VL_VERSION]                FLOAT          NULL,
    [DT_INSERT]                 DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]           DATETIME2(0)   NULL,

    CONSTRAINT [PK_L1_FACT_SALES_TRANSACTION] PRIMARY KEY CLUSTERED ([ID_FACT_SALES] ASC)
);

-- Analytics indexes
CREATE INDEX [IX_L1_FACT_DT_DEPARTURE]
    ON [L1_FACT_SALES_TRANSACTION] ([DT_DEPARTURE] ASC)
    INCLUDE ([ID_PRODUCT], [ID_AGENT], [T_INVOICE_TYPE], [AMT_REVENUE_BC]);

CREATE INDEX [IX_L1_FACT_DT_CREATED]
    ON [L1_FACT_SALES_TRANSACTION] ([DT_CREATED] ASC)
    INCLUDE ([CD_ORDER_ID], [ID_AGENT], [AMT_REVENUE_BC]);

CREATE INDEX [IX_L1_FACT_ORDER]
    ON [L1_FACT_SALES_TRANSACTION] ([CD_ORDER_ID] ASC, [CD_PRODUCT_ID] ASC)
    INCLUDE ([T_INVOICE_TYPE], [AMT_REVENUE_BC], [AMT_SUPPLIER_PRICE_BC]);
