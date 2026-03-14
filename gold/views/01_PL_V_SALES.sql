/*
================================================================================
 View: PL_V_SALES
 Layer: Gold (L1) - Semantic / Presentation Layer
 Source: L1_FACT_SALES_TRANSACTION, L1_DIM_PRODUCT, L1_DIM_SUPPLIER,
         L1_DIM_AGENT, L1_DIM_DATE
 Old equivalent: vFactSales (composite view combining Prio + Traveller + OP)
================================================================================
 Purpose:
   Public-facing view for BI tool integration (Power BI, Excel).
   Joins all Gold dimension tables to the fact table to produce a fully
   descriptive, flat dataset ready for self-service analytics.
   Applies final business logic:
     - Effective product name (AW override when available)
     - Channel classification
     - Fiscal year / quarter labels
     - P&L categorisation flags
   This view is the single point of truth for all sales reporting.
================================================================================
 NOTE: In Microsoft Fabric, this view is created in the Gold Warehouse.
       Power BI datasets connect to this view (or the underlying tables)
       via Direct Lake or Import mode.
================================================================================
*/

CREATE VIEW [dbo].[PL_V_SALES]
AS
SELECT

    -- =========================================================
    -- Transaction identifiers
    -- =========================================================
    f.[ID_FACT_SALES],
    f.[CD_TRANSACTION_ID]                                   AS CD_TRANSACTION_ID,
    f.[CD_ORDER_ID]                                         AS CD_ORDER_ID,
    f.[CD_PRODUCT_ID]                                       AS CD_ORDER_PRODUCT_ID,
    f.[CD_SALES_TRANSACTION]                                AS CD_SALES_TRANSACTION,
    f.[CD_TICKET_NUMBER]                                    AS CD_TICKET_NUMBER,
    f.[CD_INVOICE_REFERENCE]                                AS CD_INVOICE_REFERENCE,
    f.[CD_SOURCE_SYSTEM]                                    AS CD_SOURCE_SYSTEM,

    -- =========================================================
    -- Invoice classification
    -- =========================================================
    f.[T_INVOICE_TYPE]                                      AS T_INVOICE_TYPE,
    f.[CD_TYPE_AMOUNT]                                      AS CD_TYPE_AMOUNT,   -- D=Debit, C=Credit
    f.[CD_INVOICE_CATEGORY]                                 AS CD_INVOICE_CATEGORY,
    f.[CD_SALES_STATUS]                                     AS CD_SALES_STATUS,

    -- =========================================================
    -- Dates
    -- =========================================================
    f.[DT_TRANSACTION]                                      AS DT_TRANSACTION,
    CAST(f.[DT_DEPARTURE] AS DATE)                          AS DT_DEPARTURE,
    CAST(f.[DT_CREATED] AS DATE)                            AS DT_BOOKING_CREATED,
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

    f.[T_FISCAL_YEAR]                                       AS T_FISCAL_YEAR,

    -- =========================================================
    -- Booking attributes
    -- =========================================================
    f.[T_BOOKING_TYPE]                                      AS T_BOOKING_TYPE,   -- 'Trade', 'Direct'
    f.[T_BOOKING_SOURCE]                                    AS T_BOOKING_SOURCE,
    f.[T_PACKAGE_TYPE]                                      AS T_PACKAGE_TYPE,
    f.[T_LEAD_PAX_NAME]                                     AS T_LEAD_PAX_NAME,
    f.[T_PAYMENT_METHOD]                                    AS T_PAYMENT_METHOD,

    -- =========================================================
    -- Product dimension
    -- =========================================================
    f.[ID_PRODUCT]                                          AS ID_PRODUCT,
    p.[CD_PRODUCT_ID]                                       AS CD_PRODUCT_ID,
    ISNULL(p.[T_PRODUCT_NAME], 'Unknown Product')           AS T_PRODUCT_NAME,
    ISNULL(p.[T_PRODUCT_CITY],    'Unknown')                AS T_PRODUCT_CITY,
    ISNULL(p.[T_PRODUCT_REGION],  'Unknown')                AS T_PRODUCT_REGION,
    ISNULL(p.[T_PRODUCT_COUNTRY], 'Unknown')                AS T_PRODUCT_COUNTRY,
    p.[T_PRODUCT_CATEGORY]                                  AS T_PRODUCT_CATEGORY,
    p.[T_ADMIN_NAME]                                        AS T_PRODUCT_MANAGER,
    p.[T_PRODUCT_TAG]                                       AS T_PRODUCT_TAG,
    p.[FL_IS_PACKAGE]                                       AS FL_IS_PACKAGE_PRODUCT,

    -- =========================================================
    -- Supplier dimension
    -- =========================================================
    f.[ID_SUPPLIER]                                         AS ID_SUPPLIER,
    s.[CD_SUPPLIER_ID]                                      AS CD_SUPPLIER_ID,
    ISNULL(s.[T_SUPPLIER_NAME], 'Unknown Supplier')         AS T_SUPPLIER_NAME,
    s.[T_SUPPLIER_GROUP]                                    AS T_SUPPLIER_GROUP,
    s.[T_PRODUCT_MANAGER]                                   AS T_SUPPLIER_MANAGER,
    s.[T_CATEGORY]                                          AS T_SUPPLIER_CATEGORY,

    -- =========================================================
    -- Agent / Distributor dimension
    -- =========================================================
    f.[ID_AGENT]                                            AS ID_AGENT,
    a.[CD_DISTRIBUTOR_ID]                                   AS CD_DISTRIBUTOR_ID,
    ISNULL(a.[T_AGENT_NAME], 'Unknown Agent')               AS T_AGENT_NAME,
    a.[T_CHANNEL]                                           AS T_CHANNEL,         -- B2C, B2B, B2B2C
    a.[T_ACCOUNT_CHANNEL]                                   AS T_ACCOUNT_CHANNEL,
    a.[T_AGENT_GROUP_NAME]                                  AS T_AGENT_GROUP_NAME,
    a.[T_AGENT_CONSORTIA]                                   AS T_AGENT_CONSORTIA,
    a.[T_AGENT_MANAGER]                                     AS T_AGENT_MANAGER,
    a.[T_MANAGER_REGION]                                    AS T_AGENT_MANAGER_REGION,
    a.[T_HAYS_REGION]                                       AS T_HAYS_REGION,
    a.[T_HAYS_DIVISION]                                     AS T_HAYS_DIVISION,
    a.[T_TRAVEL_REGION]                                     AS T_TRAVEL_REGION,
    a.[T_TRAVEL_DIVISION]                                   AS T_TRAVEL_DIVISION,
    a.[FL_IS_TRADE_AGENT]                                   AS FL_IS_TRADE_AGENT,
    a.[FL_IS_NET_AGENT]                                     AS FL_IS_NET_AGENT,
    a.[T_DISTRIBUTOR_TYPE]                                  AS T_DISTRIBUTOR_TYPE,
    a.[T_COUNTRY]                                           AS T_AGENT_COUNTRY,

    -- =========================================================
    -- Ticket details
    -- =========================================================
    f.[T_TICKET_TYPE]                                       AS T_TICKET_TYPE,
    f.[T_PAX_TYPE]                                          AS T_PAX_TYPE,
    f.[NUM_TICKET_QUANTITY]                                 AS NUM_TICKET_QUANTITY,
    f.[T_MERCHANT_NAME]                                     AS T_MERCHANT_NAME,
    f.[T_SUPPLIER_ADMIN]                                    AS T_SUPPLIER_ADMIN,

    -- =========================================================
    -- Currency & exchange rates
    -- =========================================================
    f.[CD_SALES_CURRENCY]                                   AS CD_SALES_CURRENCY,
    f.[CD_SUPPLIER_CURRENCY]                                AS CD_SUPPLIER_CURRENCY,
    f.[CD_BASE_CURRENCY]                                    AS CD_BASE_CURRENCY,
    f.[VL_SALES_EXCHANGE_RATE]                              AS VL_SALES_EXCHANGE_RATE,
    f.[VL_SUPPLIER_EXCHANGE_RATE]                           AS VL_SUPPLIER_EXCHANGE_RATE,
    f.[CD_EXCHANGE_RATE_TYPE]                               AS CD_EXCHANGE_RATE_TYPE,

    -- =========================================================
    -- Sales amounts (transaction currency)
    -- =========================================================
    f.[AMT_REVENUE_TC]                                      AS AMT_REVENUE_TC,
    f.[AMT_GROSS_SALES_PRICE_TC]                            AS AMT_LIST_SALES_PRICE_TC,
    f.[AMT_DISCOUNT_TC]                                     AS AMT_DISCOUNT_TC,
    f.[AMT_GENERAL_TAX_TC]                                  AS AMT_GENERAL_TAX_TC,
    f.[AMT_NET_DISTRIBUTOR_FEE_TC]                          AS AMT_COMMISSION_TC,

    -- =========================================================
    -- Sales amounts (base currency GBP)
    -- =========================================================
    f.[AMT_REVENUE_BC]                                      AS AMT_REVENUE_GBP,
    f.[AMT_GROSS_SALES_PRICE_BC]                            AS AMT_LIST_SALES_PRICE_GBP,
    f.[AMT_DISCOUNT_BC]                                     AS AMT_DISCOUNT_GBP,

    -- =========================================================
    -- Supplier / cost amounts (base currency GBP)
    -- =========================================================
    f.[AMT_SUPPLIER_PRICE_TC]                               AS AMT_SUPPLIER_PRICE_TC,
    f.[AMT_SUPPLIER_PRICE_BC]                               AS AMT_SUPPLIER_PRICE_GBP,
    f.[AMT_NET_SUPPLIER_PRICE_BC]                           AS AMT_NET_SUPPLIER_PRICE_GBP,

    -- =========================================================
    -- P&L metrics (GBP) — pre-computed in fact table
    -- =========================================================
    f.[VL_NET_TICKET_ORDER_QTY]                             AS VL_NET_TICKET_ORDER_QTY,
    f.[AMT_TURNOVER_GBP]                                    AS AMT_TURNOVER_GBP,
    f.[AMT_DISCOUNTS_GBP]                                   AS AMT_DISCOUNTS_GBP,
    f.[AMT_TAX_CHARGES_GBP]                                 AS AMT_TAX_CHARGES_GBP,
    f.[AMT_GROSS_ORDER_VALUE_GBP]                           AS AMT_GROSS_ORDER_VALUE_GBP,
    f.[AMT_CANCELLED_VALUE_GBP]                             AS AMT_CANCELLED_VALUE_GBP,
    f.[AMT_NET_ORDER_VALUE_GBP]                             AS AMT_NET_ORDER_VALUE_GBP,
    f.[AMT_AGENT_COMMISSIONS_GBP]                           AS AMT_AGENT_COMMISSIONS_GBP,
    f.[AMT_NET_PRODUCT_COSTS_GBP]                           AS AMT_NET_PRODUCT_COSTS_GBP,
    f.[AMT_GROSS_MARGIN_GBP]                                AS AMT_GROSS_MARGIN_GBP,
    f.[AMT_MARKETING_COSTS_GBP]                             AS AMT_MARKETING_COSTS_GBP,
    f.[AMT_OTHER_COSTS_GBP]                                 AS AMT_OTHER_COSTS_GBP,
    f.[AMT_NET_MARGIN_GBP]                                  AS AMT_NET_MARGIN_GBP,

    -- =========================================================
    -- Supplier recognition
    -- =========================================================
    f.[DT_SUPPLIER_RECOGNITION]                             AS DT_SUPPLIER_RECOGNITION,
    f.[FL_IS_ACCRUAL]                                       AS FL_IS_ACCRUAL,

    -- =========================================================
    -- Helper flags for report filtering
    -- =========================================================
    CASE WHEN f.[T_INVOICE_TYPE] IN ('Revenue', 'Refunds', 'Discounts') THEN 1 ELSE 0 END
                                                            AS FL_IS_REVENUE_LINE,
    CASE WHEN f.[T_INVOICE_TYPE] IN ('Tour Commissions', 'VAT Commissions') THEN 1 ELSE 0 END
                                                            AS FL_IS_COMMISSION_LINE,
    CASE WHEN f.[CD_TYPE_AMOUNT] = 'D' THEN 1 ELSE 0 END   AS FL_IS_DEBIT,
    CASE WHEN f.[CD_SALES_STATUS] = 'Cancelled' THEN 1 ELSE 0 END
                                                            AS FL_IS_CANCELLED,

    -- =========================================================
    -- Audit
    -- =========================================================
    f.[DT_INSERT]                                           AS DT_FACT_INSERT,
    f.[DT_LAST_UPDATED]                                     AS DT_FACT_LAST_UPDATED,
    f.[VL_VERSION]                                          AS VL_TRANSACTION_VERSION

FROM [L1_FACT_SALES_TRANSACTION] f

-- Product dimension
LEFT JOIN [L1_DIM_PRODUCT] p
    ON p.[ID_PRODUCT] = f.[ID_PRODUCT]

-- Supplier dimension
LEFT JOIN [L1_DIM_SUPPLIER] s
    ON s.[ID_SUPPLIER] = f.[ID_SUPPLIER]

-- Agent dimension
LEFT JOIN [L1_DIM_AGENT] a
    ON a.[ID_AGENT] = f.[ID_AGENT]

-- Date dimension: departure date
LEFT JOIN [L1_DIM_DATE] dep
    ON dep.[DT_DATE] = CAST(f.[DT_DEPARTURE] AS DATE)

-- Date dimension: booking created date
LEFT JOIN [L1_DIM_DATE] crt
    ON crt.[DT_DATE] = CAST(f.[DT_CREATED] AS DATE);
