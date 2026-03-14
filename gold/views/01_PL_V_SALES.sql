/*
================================================================================
 View: PL_V_SALES
 Layer: Gold (L1) - Semantic / Presentation Layer
 Source: L1_FACT_SALES_TRANSACTION, L1_DIM_PRODUCT, L1_DIM_SUPPLIER,
         L1_DIM_AGENT, L1_DIM_DATE
================================================================================
 Purpose:
   Public-facing view for BI tool integration (Power BI, Excel).
   Exposes all real signed measures from the fact table plus computed P&L metrics.

   Granularity: one row per transaction line (same as fact table).
   Signed amounts: confirmed = positive, refunded/cancelled = negative.
   Aggregating any measure across a period naturally nets out refunds.

 Key P&L measures (all in GBP):
   AMT_SALE_PRICE_GBP            — gross sale price (rack / list)
   AMT_NET_SALE_PRICE_GBP        — net sale price after distributor discount
   AMT_SUPPLIER_PRICE_GBP        — cost of goods (supplier buy rate)
   AMT_AGENT_COMMISSION_GBP      — net commission owed to agent
   AMT_VAT_ON_COMMISSION_GBP     — VAT on agent commission
   AMT_TOTAL_COMMISSION_COST_GBP — total agent commission cost (incl. VAT)
   AMT_GROSS_MARGIN_GBP          — net sale price - supplier cost - total commission cost
================================================================================
*/

CREATE VIEW [dbo].[PL_V_SALES]
AS
SELECT

    -- =========================================================
    -- Transaction identifiers
    -- =========================================================
    f.[ID_FACT_SALES],
    f.[CD_TRANSACTION_ID],
    f.[CD_ORDER_ID],
    f.[CD_PRODUCT_ID]                                       AS CD_ORDER_PRODUCT_ID,
    f.[CD_TICKET_NUMBER],
    f.[CD_INVOICE_REFERENCE],
    f.[CD_SOURCE_SYSTEM],

    -- =========================================================
    -- Order / booking status
    -- =========================================================
    f.[CD_ORDER_STATUS],
    f.[FL_IS_REFUND],                                       -- 1 = refund/cancellation row

    -- =========================================================
    -- Dates
    -- =========================================================
    f.[DT_TRANSACTION],
    CAST(f.[DT_DEPARTURE]  AS DATE)                         AS DT_DEPARTURE,
    CAST(f.[DT_CREATED]    AS DATE)                         AS DT_BOOKING_CREATED,
    CAST(f.[DT_CANCELLATION] AS DATE)                       AS DT_CANCELLATION,

    -- Date dimension attributes (departure date)
    dep.[T_FISCAL_YEAR]                                     AS T_DEPARTURE_FISCAL_YEAR,
    dep.[T_FISCAL_QUARTER]                                  AS T_DEPARTURE_FISCAL_QUARTER,
    dep.[NUM_YEAR]                                          AS NUM_DEPARTURE_YEAR,
    dep.[NUM_MONTH]                                         AS NUM_DEPARTURE_MONTH,
    dep.[T_MONTH_NAME]                                      AS T_DEPARTURE_MONTH,
    dep.[T_MONTH_SHORT]                                     AS T_DEPARTURE_MONTH_SHORT,

    -- Date dimension attributes (booking created date)
    crt.[T_FISCAL_YEAR]                                     AS T_CREATED_FISCAL_YEAR,
    crt.[NUM_YEAR]                                          AS NUM_CREATED_YEAR,
    crt.[NUM_MONTH]                                         AS NUM_CREATED_MONTH,

    f.[T_FISCAL_YEAR],

    -- =========================================================
    -- Booking attributes
    -- =========================================================
    f.[T_BOOKING_TYPE],                                     -- 'Trade', 'Direct'
    f.[T_BOOKING_SOURCE],
    f.[T_PACKAGE_TYPE],
    f.[T_LEAD_PAX_NAME],
    f.[T_PAYMENT_METHOD],

    -- =========================================================
    -- Product dimension
    -- =========================================================
    f.[ID_PRODUCT],
    p.[CD_PRODUCT_ID]                                       AS CD_PRODUCT_ID,
    ISNULL(p.[T_PRODUCT_NAME],    'Unknown Product')        AS T_PRODUCT_NAME,
    ISNULL(p.[T_PRODUCT_CITY],    'Unknown')                AS T_PRODUCT_CITY,
    ISNULL(p.[T_PRODUCT_REGION],  'Unknown')                AS T_PRODUCT_REGION,
    ISNULL(p.[T_PRODUCT_COUNTRY], 'Unknown')                AS T_PRODUCT_COUNTRY,
    p.[T_PRODUCT_CATEGORY],
    p.[T_ADMIN_NAME]                                        AS T_PRODUCT_MANAGER,
    p.[T_PRODUCT_TAG],
    p.[FL_IS_PACKAGE]                                       AS FL_IS_PACKAGE_PRODUCT,

    -- =========================================================
    -- Supplier dimension
    -- =========================================================
    f.[ID_SUPPLIER],
    s.[CD_SUPPLIER_ID],
    ISNULL(s.[T_SUPPLIER_NAME],   'Unknown Supplier')       AS T_SUPPLIER_NAME,
    s.[T_SUPPLIER_GROUP],
    s.[T_PRODUCT_MANAGER]                                   AS T_SUPPLIER_MANAGER,
    s.[T_CATEGORY]                                          AS T_SUPPLIER_CATEGORY,

    -- =========================================================
    -- Agent / Distributor dimension
    -- =========================================================
    f.[ID_AGENT],
    a.[CD_DISTRIBUTOR_ID],
    ISNULL(a.[T_AGENT_NAME],      'Unknown Agent')          AS T_AGENT_NAME,
    a.[T_CHANNEL],                                          -- 'B2C', 'B2B', 'B2B2C'
    a.[T_ACCOUNT_CHANNEL],
    a.[T_AGENT_GROUP_NAME],
    a.[T_AGENT_CONSORTIA],
    a.[T_AGENT_MANAGER],
    a.[T_MANAGER_REGION]                                    AS T_AGENT_MANAGER_REGION,
    a.[T_HAYS_REGION],
    a.[T_HAYS_DIVISION],
    a.[T_TRAVEL_REGION],
    a.[T_TRAVEL_DIVISION],
    a.[FL_IS_TRADE_AGENT],
    a.[FL_IS_NET_AGENT],
    a.[T_DISTRIBUTOR_TYPE],
    a.[T_COUNTRY]                                           AS T_AGENT_COUNTRY,

    -- =========================================================
    -- Ticket details
    -- =========================================================
    f.[T_TICKET_TYPE],
    f.[T_PAX_TYPE],
    f.[NUM_TICKET_QUANTITY],                                -- Signed: positive=sale, negative=refund
    f.[T_MERCHANT_NAME],
    f.[T_SUPPLIER_ADMIN],

    -- =========================================================
    -- Currency & exchange rates
    -- =========================================================
    f.[CD_SALES_CURRENCY],
    f.[CD_SUPPLIER_CURRENCY],
    f.[CD_BASE_CURRENCY],
    f.[VL_SALES_EXCHANGE_RATE],
    f.[VL_SUPPLIER_EXCHANGE_RATE],
    f.[CD_EXCHANGE_RATE_TYPE],

    -- =========================================================
    -- Sales amounts — Transaction Currency (TC)
    -- Signed: positive = confirmed, negative = refund
    -- =========================================================
    f.[AMT_SALE_PRICE_TC],
    f.[AMT_NET_SALE_PRICE_TC],
    f.[AMT_LIST_PRICE_TC],
    f.[AMT_DISTRIBUTOR_DISCOUNT_TC],
    f.[AMT_GENERAL_TAX_TC],

    -- =========================================================
    -- Supplier amounts — TC
    -- =========================================================
    f.[AMT_SUPPLIER_PRICE_TC],
    f.[AMT_NET_SUPPLIER_PRICE_TC],

    -- =========================================================
    -- Fee amounts — TC
    -- =========================================================
    f.[AMT_NET_DISTRIBUTOR_FEE_TC]                          AS AMT_AGENT_COMMISSION_TC,
    f.[AMT_DISTRIBUTOR_TAX_TC]                              AS AMT_VAT_ON_COMMISSION_TC,
    f.[AMT_RESELLER_FEE_TC],
    f.[AMT_MERCHANT_FEE_TC],
    f.[AMT_AFFILIATE_FEE_TC],

    -- =========================================================
    -- Sales amounts — Base Currency GBP
    -- =========================================================
    f.[AMT_SALE_PRICE_BC]                                   AS AMT_SALE_PRICE_GBP,
    f.[AMT_NET_SALE_PRICE_BC]                               AS AMT_NET_SALE_PRICE_GBP,
    f.[AMT_LIST_PRICE_BC]                                   AS AMT_LIST_PRICE_GBP,
    f.[AMT_DISTRIBUTOR_DISCOUNT_BC]                         AS AMT_DISTRIBUTOR_DISCOUNT_GBP,
    f.[AMT_GENERAL_TAX_BC]                                  AS AMT_GENERAL_TAX_GBP,

    -- =========================================================
    -- Supplier / cost amounts — GBP
    -- =========================================================
    f.[AMT_SUPPLIER_PRICE_BC]                               AS AMT_SUPPLIER_PRICE_GBP,
    f.[AMT_NET_SUPPLIER_PRICE_BC]                           AS AMT_NET_SUPPLIER_PRICE_GBP,

    -- =========================================================
    -- Commission measures — GBP
    -- =========================================================
    f.[AMT_AGENT_COMMISSION_BC]                             AS AMT_AGENT_COMMISSION_GBP,
    f.[AMT_VAT_ON_COMMISSION_BC]                            AS AMT_VAT_ON_COMMISSION_GBP,
    f.[AMT_TOTAL_COMMISSION_COST_BC]                        AS AMT_TOTAL_COMMISSION_COST_GBP,

    -- =========================================================
    -- Computed P&L measures (GBP) — derived in view
    -- All measures net naturally across refunds via signed values
    -- =========================================================

    -- Gross Margin = Net Sale Price - Supplier Cost - Total Commission Cost
    ISNULL(f.[AMT_NET_SALE_PRICE_BC], 0)
        - ISNULL(f.[AMT_SUPPLIER_PRICE_BC], 0)
        - ISNULL(f.[AMT_TOTAL_COMMISSION_COST_BC], 0)       AS AMT_GROSS_MARGIN_GBP,

    -- Gross Margin % = Gross Margin / Net Sale Price (0 when no revenue)
    CASE WHEN ISNULL(f.[AMT_NET_SALE_PRICE_BC], 0) = 0 THEN NULL
         ELSE (ISNULL(f.[AMT_NET_SALE_PRICE_BC], 0)
                   - ISNULL(f.[AMT_SUPPLIER_PRICE_BC], 0)
                   - ISNULL(f.[AMT_TOTAL_COMMISSION_COST_BC], 0))
              / f.[AMT_NET_SALE_PRICE_BC]
    END                                                     AS PCT_GROSS_MARGIN,

    -- Other fee amounts (GBP) for full cost reconciliation
    f.[AMT_RESELLER_FEE_BC]                                 AS AMT_RESELLER_FEE_GBP,
    f.[AMT_MERCHANT_FEE_BC]                                 AS AMT_MERCHANT_FEE_GBP,
    f.[AMT_AFFILIATE_FEE_BC]                                AS AMT_AFFILIATE_FEE_GBP,

    -- =========================================================
    -- Audit
    -- =========================================================
    f.[VL_VERSION]                                          AS VL_TRANSACTION_VERSION,
    f.[DT_INSERT]                                           AS DT_FACT_INSERT,
    f.[DT_LAST_UPDATED]                                     AS DT_FACT_LAST_UPDATED

FROM [L1_FACT_SALES_TRANSACTION] f

LEFT JOIN [L1_DIM_PRODUCT] p
    ON p.[ID_PRODUCT]  = f.[ID_PRODUCT]

LEFT JOIN [L1_DIM_SUPPLIER] s
    ON s.[ID_SUPPLIER] = f.[ID_SUPPLIER]

LEFT JOIN [L1_DIM_AGENT] a
    ON a.[ID_AGENT]    = f.[ID_AGENT]

-- Date dimension: departure date
LEFT JOIN [L1_DIM_DATE] dep
    ON dep.[DT_DATE]   = CAST(f.[DT_DEPARTURE] AS DATE)

-- Date dimension: booking created date
LEFT JOIN [L1_DIM_DATE] crt
    ON crt.[DT_DATE]   = CAST(f.[DT_CREATED] AS DATE);
