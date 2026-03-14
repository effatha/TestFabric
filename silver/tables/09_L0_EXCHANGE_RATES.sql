/*
================================================================================
 Table: L0_EXCHANGE_RATES
 Layer: Silver (L0) - Reference
 Source: BOE_API_EXCHANGE_RATES (Bronze), MD_LIST_EXCHANGE_RATES (Bronze)
 Old equivalent: [AWTasks].dbo.ExchangeRates + [AWTasks].dbo.BOEExchangeRates
================================================================================
 Purpose:
   Consolidated exchange rate reference table used by the Gold ETL to convert
   amounts from transaction/supplier currency to base currency (GBP).
   Combines:
     - BOE spot rates (actuals for past departures)
     - AW budget rates (TY/NY/FY columns for future departures)
     - Manual override rates (for specific product/agent/date combinations)
================================================================================
*/

CREATE TABLE [L0_EXCHANGE_RATES] (

    [ID_EXCHANGE_RATE]           INT             NOT NULL,

    -- Currency & period
    [CD_CURRENCY_CODE]           NVARCHAR(10)    NOT NULL,   -- ISO currency code (e.g. 'USD', 'EUR')
    [DT_EFFECTIVE_FROM]          DATE            NOT NULL,   -- Rate effective from
    [DT_EFFECTIVE_TO]            DATE            NULL,       -- Rate effective to (NULL = open-ended)
    [CD_RATE_TYPE]               NVARCHAR(50)    NOT NULL,   -- 'Actual', 'Budget', 'BOE_Spot', 'Override'

    -- Rate values
    [VL_EXCHANGE_RATE]           DECIMAL(19,6)   NOT NULL,   -- Rate to convert to GBP (1 unit of currency = X GBP)
    [VL_RATE_TY]                 DECIMAL(19,6)   NULL,       -- Budget: This Year rate
    [VL_RATE_NY]                 DECIMAL(19,6)   NULL,       -- Budget: Next Year rate
    [VL_RATE_FY]                 DECIMAL(19,6)   NULL,       -- Budget: Future Year rate

    -- Override scope (NULL = applies to all)
    [CD_PRODUCT_IDS]             NVARCHAR(MAX)   NULL,       -- Comma-separated product IDs (for override)
    [CD_AGENT_IDS]               NVARCHAR(MAX)   NULL,       -- Comma-separated agent IDs (for override)
    [DT_TRAVEL_START]            DATE            NULL,       -- Override: travel window start
    [DT_TRAVEL_END]              DATE            NULL,       -- Override: travel window end
    [DT_BOOKING_START]           DATE            NULL,       -- Override: booking window start
    [DT_BOOKING_END]             DATE            NULL,       -- Override: booking window end

    -- Source tracking
    [CD_SOURCE]                  NVARCHAR(50)    NULL,       -- 'BOE', 'AW_BUDGET', 'MANUAL'
    [FL_IS_ACTIVE]               BIT             NOT NULL DEFAULT 1,

    [DT_INSERT]                  DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT [PK_L0_EXCHANGE_RATES] PRIMARY KEY CLUSTERED ([ID_EXCHANGE_RATE] ASC)
);

CREATE INDEX [IX_L0_EXCHANGE_RATES_LOOKUP]
    ON [L0_EXCHANGE_RATES] ([CD_CURRENCY_CODE] ASC, [CD_RATE_TYPE] ASC, [DT_EFFECTIVE_FROM] ASC, [DT_EFFECTIVE_TO] ASC);
