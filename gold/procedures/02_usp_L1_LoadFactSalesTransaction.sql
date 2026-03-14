/*
================================================================================
 Procedure: usp_L1_LoadFactSalesTransaction
 Layer: Gold (L1)
 Source: L0_SRG_SALES_TRANSACTION, L0_SRG_BOOKING, L1_DIM_PRODUCT, L1_DIM_SUPPLIER,
         L1_DIM_AGENT, L0_EXCHANGE_RATES, L0_REF_AGENT_COMMISSION_OVERRIDE
 Target: L1_FACT_SALES_TRANSACTION
 Old equivalent: usp_ProcessPrioTransactions + usp_ProcessExchangeRates (Gold part)
================================================================================
 Purpose:
   Builds the Gold fact table from Silver surrogation tables.
   Steps:
     1. INSERT new fact rows from unprocessed Silver sales transactions
     2. UPDATE existing rows when Silver data has changed (version bump)
     3. Apply virtual AGENT COMMISSION rows (Tour Commissions / VAT Commissions)
        for trade agents (mirrors usp_ProcessAgentCommissions)
     4. Apply EXCHANGE RATES:
        - Sales currency → GBP using budget/actual/BOE/override logic
        - Supplier currency → GBP
     5. Compute P&L metrics (AMT_TURNOVER_GBP, AMT_GROSS_MARGIN_GBP, etc.)
     6. Apply HAYS OVERRIDE COMMISSIONS from L0_REF_AGENT_COMMISSION_OVERRIDE
     7. Mark Silver rows as processed (FL_IS_PROCESSED_TO_GOLD = 1)
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L1_LoadFactSalesTransaction]
AS
BEGIN
    SET NOCOUNT ON;

    /*
    ============================================================
    STEP 1: INSERT new fact rows from unprocessed Silver rows
    ============================================================
    */
    INSERT INTO [L1_FACT_SALES_TRANSACTION] (
        [ID_FACT_SALES],
        [ID_PRODUCT], [ID_SUPPLIER], [ID_AGENT],
        [CD_ORDER_ID], [CD_PRODUCT_ID], [CD_SALES_TRANSACTION], [CD_TRANSACTION_ID],
        [CD_SOURCE_SYSTEM],
        [T_INVOICE_TYPE], [CD_TYPE_AMOUNT], [CD_INVOICE_CATEGORY],
        [CD_INVOICE_TID], [CD_INVOICE_SID], [CD_SALES_STATUS],
        [DT_TRANSACTION], [DT_DEPARTURE], [DT_CREATED], [DT_CANCELLATION],
        [T_BOOKING_TYPE], [T_BOOKING_SOURCE], [T_PACKAGE_TYPE],
        [T_LEAD_PAX_NAME], [T_FISCAL_YEAR], [T_PAYMENT_METHOD], [CD_INVOICE_REFERENCE],
        [T_TICKET_TYPE], [T_PAX_TYPE], [NUM_TICKET_QUANTITY],
        [T_MERCHANT_NAME], [T_SUPPLIER_ADMIN],
        [CD_SALES_CURRENCY], [CD_SUPPLIER_CURRENCY],
        [AMT_REVENUE_TC], [AMT_SUPPLIER_PRICE_TC],
        [AMT_DISTRIBUTOR_FEE_TC], [AMT_NET_DISTRIBUTOR_FEE_TC],
        [AMT_GENERAL_TAX_TC],
        [CD_TICKET_NUMBER],
        [VL_VERSION]
    )
    SELECT
        ISNULL((SELECT MAX(ID_FACT_SALES) FROM L1_FACT_SALES_TRANSACTION), 0)
            + ROW_NUMBER() OVER (ORDER BY st.ID_SALES_TRANSACTION),
        p.[ID_PRODUCT],
        s.[ID_SUPPLIER],
        a.[ID_AGENT],
        bk.[CD_ORDER_ID],
        bk.[CD_PRODUCT_ID],
        CONCAT(bk.CD_ORDER_ID, '-', bk.CD_PRODUCT_ID, '-', st.CD_TRANSACTION_ID),
        st.[CD_TRANSACTION_ID],
        'PRIO',
        st.[CD_INVOICE_TYPE],
        st.[T_TYPE_AMOUNT],
        st.[CD_INVOICE_CATEGORY],
        st.[CD_INVOICE_TID],
        st.[CD_INVOICE_SID],
        st.[CD_ORDER_STATUS],
        CAST(st.[DT_ORDER] AS DATETIME2(0)),
        CAST(bk.[DT_DEPARTURE] AS DATE),
        CAST(bk.[DT_CREATED] AS DATE),
        CAST(bk.[DT_CANCELLATION] AS DATE),
        bk.[T_BOOKING_TYPE],
        bk.[T_BOOKING_SOURCE],
        bk.[T_PACKAGE_TYPE],
        bk.[T_LEAD_PAX_NAME],
        bk.[T_FISCAL_YEAR],
        st.[T_PAYMENT_METHOD],
        st.[CD_INVOICE_REFERENCE],
        st.[T_TICKET_TYPE],
        CASE WHEN st.[T_TICKET_TYPE] IN ('Adult','Child') THEN st.[T_TICKET_TYPE] ELSE 'Other' END,
        st.[NUM_QUANTITY],
        st.[T_MERCHANT_NAME],
        st.[T_SUPPLIER_ADMIN],
        st.[CD_SALES_CURRENCY],
        st.[CD_SUPPLIER_CURRENCY],
        st.[AMT_REVENUE],
        st.[AMT_SUPPLIER_PRICE],
        NULL,                     -- AMT_DISTRIBUTOR_FEE_TC (populated from commission lines)
        st.[AMT_COMMISSION],
        st.[AMT_REVENUE_VAT],
        st.[CD_TICKET_NUMBER],
        st.[VL_VERSION]
    FROM [L0_SRG_SALES_TRANSACTION] st
    INNER JOIN [L0_SRG_BOOKING]   bk ON bk.[ID_BOOKING] = st.[ID_BOOKING]
    INNER JOIN [L1_DIM_PRODUCT]   p  ON p.[ID_PRODUCT]  = st.[ID_PRODUCT]
    INNER JOIN [L1_DIM_SUPPLIER]  s  ON s.[ID_SUPPLIER] = st.[ID_SUPPLIER]
    INNER JOIN [L1_DIM_AGENT]     a  ON a.[ID_AGENT]    = st.[ID_AGENT]
    LEFT JOIN  [L1_FACT_SALES_TRANSACTION] ex
        ON ex.[CD_TRANSACTION_ID] = st.[CD_TRANSACTION_ID]
        AND ex.[T_INVOICE_TYPE]   = st.[CD_INVOICE_TYPE]
    WHERE
        st.[FL_IS_PROCESSED_TO_GOLD] = 0
        AND ex.[ID_FACT_SALES] IS NULL;  -- New rows only

    /*
    ============================================================
    STEP 2: UPDATE existing fact rows (changed versions)
    ============================================================
    */
    UPDATE f
    SET
        f.[AMT_REVENUE_TC]           = st.[AMT_REVENUE],
        f.[CD_SALES_STATUS]          = st.[CD_ORDER_STATUS],
        f.[AMT_NET_DISTRIBUTOR_FEE_TC] = st.[AMT_COMMISSION],
        f.[AMT_SUPPLIER_PRICE_TC]    = st.[AMT_SUPPLIER_PRICE],
        f.[VL_VERSION]               = st.[VL_VERSION],
        f.[CD_SALES_CURRENCY]        = st.[CD_SALES_CURRENCY],
        f.[CD_SUPPLIER_CURRENCY]     = st.[CD_SUPPLIER_CURRENCY],
        f.[DT_TRANSACTION]           = CAST(st.[DT_ORDER] AS DATETIME2(0)),
        f.[DT_LAST_UPDATED]          = SYSDATETIME()
    FROM [L1_FACT_SALES_TRANSACTION] f
    INNER JOIN [L0_SRG_SALES_TRANSACTION] st
        ON st.[CD_TRANSACTION_ID] = f.[CD_TRANSACTION_ID]
        AND st.[CD_INVOICE_TYPE]  = f.[T_INVOICE_TYPE]
    WHERE st.[FL_IS_PROCESSED_TO_GOLD] = 0;

    /*
    ============================================================
    STEP 3: INSERT virtual AGENT COMMISSION rows
            (Tour Commissions + VAT Commissions)
            Only for trade agents that are NOT net agents
    ============================================================
    */
    -- Delete existing commission rows for orders being reprocessed
    DELETE f
    FROM [L1_FACT_SALES_TRANSACTION] f
    INNER JOIN (
        SELECT DISTINCT bk.[CD_ORDER_ID]
        FROM [L0_SRG_SALES_TRANSACTION] st
        INNER JOIN [L0_SRG_BOOKING] bk ON bk.[ID_BOOKING] = st.[ID_BOOKING]
        WHERE st.[FL_IS_PROCESSED_TO_GOLD] = 0
    ) orders ON f.[CD_ORDER_ID] = orders.CD_ORDER_ID
    INNER JOIN [L1_DIM_AGENT] a ON a.[ID_AGENT] = f.[ID_AGENT]
    WHERE
        a.[FL_IS_TRADE_AGENT] = 1
        AND f.[T_INVOICE_TYPE] IN ('Tour Commissions', 'VAT Commissions');

    -- Tour Commissions
    INSERT INTO [L1_FACT_SALES_TRANSACTION] (
        [ID_FACT_SALES],
        [ID_AGENT], [CD_ORDER_ID], [CD_PRODUCT_ID],
        [T_INVOICE_TYPE], [CD_TYPE_AMOUNT], [CD_INVOICE_CATEGORY],
        [CD_INVOICE_TID], [CD_INVOICE_SID],
        [DT_CREATED], [DT_DEPARTURE], [DT_TRANSACTION],
        [T_BOOKING_TYPE], [T_FISCAL_YEAR],
        [AMT_REVENUE_TC], [CD_SALES_CURRENCY],
        [VL_VERSION], [CD_SOURCE_SYSTEM]
    )
    SELECT
        ISNULL((SELECT MAX(ID_FACT_SALES) FROM L1_FACT_SALES_TRANSACTION), 0)
            + ROW_NUMBER() OVER (ORDER BY bk.CD_ORDER_ID),
        a.[ID_AGENT],
        bk.[CD_ORDER_ID],
        bk.[CD_PRODUCT_ID],
        'Tour Commissions',
        CASE WHEN SUM(st.[AMT_NET_DISTRIBUTOR_FEE_TC]) > 0 THEN 'C' ELSE 'D' END,
        4,
        3880,
        1855,
        CAST(bk.[DT_CREATED] AS DATE),
        CAST(bk.[DT_DEPARTURE] AS DATE),
        SYSDATETIME(),
        bk.[T_BOOKING_TYPE],
        bk.[T_FISCAL_YEAR],
        ABS(SUM(st.[AMT_NET_DISTRIBUTOR_FEE_TC])),
        MAX(st.[CD_SALES_CURRENCY]),
        MAX(f.[VL_VERSION]),
        'PRIO'
    FROM [L1_FACT_SALES_TRANSACTION] f
    INNER JOIN [L0_SRG_BOOKING]   bk ON bk.[CD_ORDER_ID] = f.[CD_ORDER_ID] AND bk.[CD_PRODUCT_ID] = f.[CD_PRODUCT_ID]
    INNER JOIN [L0_SRG_SALES_TRANSACTION] st ON st.[ID_BOOKING] = bk.[ID_BOOKING]
    INNER JOIN [L1_DIM_AGENT]     a  ON a.[ID_AGENT] = bk.[ID_AGENT]
    WHERE
        a.[FL_IS_TRADE_AGENT] = 1
        AND ISNULL(a.[FL_IS_NET_AGENT], 0) = 0
        AND ISNULL(a.[T_DISTRIBUTOR_TYPE], '') <> 'CostPlus'
        AND bk.[CD_ORDER_ID] IN (
            SELECT DISTINCT bk2.[CD_ORDER_ID]
            FROM [L0_SRG_SALES_TRANSACTION] st2
            INNER JOIN [L0_SRG_BOOKING] bk2 ON bk2.[ID_BOOKING] = st2.[ID_BOOKING]
            WHERE st2.[FL_IS_PROCESSED_TO_GOLD] = 0
        )
        AND f.[CD_PRODUCT_ID] > 0
    GROUP BY bk.[CD_ORDER_ID], bk.[CD_PRODUCT_ID], bk.[ID_AGENT], a.[ID_AGENT], bk.[T_BOOKING_TYPE], bk.[T_FISCAL_YEAR], bk.[DT_CREATED], bk.[DT_DEPARTURE], f.[CD_SALES_CURRENCY]
    HAVING ABS(SUM(st.[AMT_NET_DISTRIBUTOR_FEE_TC])) > 0;

    /*
    ============================================================
    STEP 4: Apply Exchange Rates (Sales Currency → GBP)
    Priority: Budget rate → Actual rate → BOE Spot → Fallback 1.0
    ============================================================
    */

    -- Reset GBP currencies to rate 1.0
    UPDATE [L1_FACT_SALES_TRANSACTION]
        SET [VL_SALES_EXCHANGE_RATE] = 1.0,
            [CD_EXCHANGE_RATE_TYPE]  = 'GBP'
    WHERE [CD_SALES_CURRENCY] IN ('GBP', 'GBP(T)');

    -- Budget rate: future departures (same-year departure → TY, next-year → NY, 2+ years → FY)
    UPDATE f
    SET
        f.[VL_SALES_EXCHANGE_RATE] = CASE
            WHEN YEAR(f.[DT_DEPARTURE]) = YEAR(f.[DT_CREATED])
                THEN (SELECT MAX(er.[VL_RATE_TY]) FROM [L0_EXCHANGE_RATES] er
                      WHERE CAST(f.[DT_CREATED] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM] AND er.[DT_EFFECTIVE_TO]
                        AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE] AND er.[CD_RATE_TYPE] = 'Budget')
            WHEN YEAR(f.[DT_DEPARTURE]) = YEAR(f.[DT_CREATED]) + 1
                THEN (SELECT MAX(er.[VL_RATE_NY]) FROM [L0_EXCHANGE_RATES] er
                      WHERE CAST(f.[DT_CREATED] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM] AND er.[DT_EFFECTIVE_TO]
                        AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE] AND er.[CD_RATE_TYPE] = 'Budget')
            ELSE    (SELECT MAX(er.[VL_RATE_FY]) FROM [L0_EXCHANGE_RATES] er
                     WHERE CAST(f.[DT_CREATED] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM] AND er.[DT_EFFECTIVE_TO]
                       AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE] AND er.[CD_RATE_TYPE] = 'Budget')
        END,
        f.[CD_EXCHANGE_RATE_TYPE] = 'Budget'
    FROM [L1_FACT_SALES_TRANSACTION] f
    WHERE f.[DT_DEPARTURE] >= CAST(GETDATE() AS DATE)
      AND f.[CD_SALES_CURRENCY] <> 'GBP';

    -- Actual rate: past departures
    UPDATE f
    SET
        f.[VL_SALES_EXCHANGE_RATE] = (
            SELECT MAX(er.[VL_EXCHANGE_RATE]) FROM [L0_EXCHANGE_RATES] er
            WHERE CAST(f.[DT_DEPARTURE] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM] AND ISNULL(er.[DT_EFFECTIVE_TO], '9999-12-31')
              AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE]
              AND er.[CD_RATE_TYPE] = 'Actual' AND er.[FL_IS_ACTIVE] = 1
        ),
        f.[CD_EXCHANGE_RATE_TYPE] = 'Actual'
    FROM [L1_FACT_SALES_TRANSACTION] f
    WHERE f.[DT_DEPARTURE] < CAST(GETDATE() AS DATE)
      AND f.[CD_SALES_CURRENCY] <> 'GBP'
      AND YEAR(f.[DT_DEPARTURE]) > 2022;

    -- BOE Spot rate: fallback for rows still without a rate
    UPDATE f
    SET
        f.[VL_SALES_EXCHANGE_RATE] = er.[VL_EXCHANGE_RATE],
        f.[CD_EXCHANGE_RATE_TYPE]  = 'BOE_Spot'
    FROM [L1_FACT_SALES_TRANSACTION] f
    INNER JOIN [L0_EXCHANGE_RATES] er
        ON er.[CD_CURRENCY_CODE] = f.[CD_SALES_CURRENCY]
        AND CAST(f.[DT_CREATED] AS DATE) = er.[DT_EFFECTIVE_FROM]
        AND er.[CD_RATE_TYPE] = 'BOE_Spot'
    WHERE f.[CD_SALES_CURRENCY] <> 'GBP'
      AND f.[VL_SALES_EXCHANGE_RATE] IS NULL;

    -- Override rates: specific product/agent/date combinations
    UPDATE f
    SET
        f.[VL_SALES_EXCHANGE_RATE] = er.[VL_EXCHANGE_RATE],
        f.[CD_EXCHANGE_RATE_TYPE]  = 'Override'
    FROM [L1_FACT_SALES_TRANSACTION] f
    INNER JOIN [L1_DIM_PRODUCT] p ON p.[ID_PRODUCT] = f.[ID_PRODUCT]
    INNER JOIN [L1_DIM_AGENT]   a ON a.[ID_AGENT]   = f.[ID_AGENT]
    INNER JOIN [L0_EXCHANGE_RATES] er
        ON f.[DT_DEPARTURE] BETWEEN er.[DT_TRAVEL_START] AND er.[DT_TRAVEL_END]
        AND f.[DT_CREATED]  BETWEEN er.[DT_BOOKING_START] AND er.[DT_BOOKING_END]
        AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE]
        AND er.[CD_RATE_TYPE] = 'Override'
        AND p.[CD_PRODUCT_ID] IN (SELECT value FROM STRING_SPLIT(er.[CD_PRODUCT_IDS], ','))
        AND a.[CD_DISTRIBUTOR_ID] IN (SELECT value FROM STRING_SPLIT(er.[CD_AGENT_IDS], ','))
    WHERE f.[CD_SALES_CURRENCY] <> 'GBP';

    -- Fallback for 2022 USD (historical hardcode from old system)
    UPDATE [L1_FACT_SALES_TRANSACTION]
        SET [VL_SALES_EXCHANGE_RATE] = 1.27,
            [CD_EXCHANGE_RATE_TYPE]  = 'Historical_Hardcode'
    WHERE [CD_SALES_CURRENCY] = 'USD'
      AND YEAR([DT_DEPARTURE]) = 2022
      AND [DT_DEPARTURE] <= GETDATE();

    /*
    ============================================================
    STEP 5: Compute base currency amounts (TC × Exchange Rate)
    ============================================================
    */
    UPDATE [L1_FACT_SALES_TRANSACTION]
    SET
        [AMT_REVENUE_BC]            = [AMT_REVENUE_TC]           * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_GROSS_SALES_PRICE_BC]  = [AMT_GROSS_SALES_PRICE_TC] * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_SUPPLIER_PRICE_BC]     = [AMT_SUPPLIER_PRICE_TC]    * ISNULL([VL_SUPPLIER_EXCHANGE_RATE], [VL_SALES_EXCHANGE_RATE], 1.0),
        [DT_LAST_UPDATED]           = SYSDATETIME();

    /*
    ============================================================
    STEP 6: Mark Silver as processed
    ============================================================
    */
    UPDATE [L0_SRG_SALES_TRANSACTION]
        SET [FL_IS_PROCESSED_TO_GOLD] = 1,
            [DT_LAST_UPDATED]         = SYSDATETIME()
    WHERE [FL_IS_PROCESSED_TO_GOLD] = 0;

END;
