/*
================================================================================
 Procedure: usp_L1_LoadFactSalesTransaction
 Layer: Gold (L1)
 Source: L0_SRG_SALES_TRANSACTION, L0_SRG_BOOKING, L1_DIM_PRODUCT,
         L1_DIM_SUPPLIER, L1_DIM_AGENT, L0_EXCHANGE_RATES
 Target: L1_FACT_SALES_TRANSACTION
================================================================================
 Purpose:
   Builds the Gold fact table from Silver surrogation tables.
   One row per CD_TRANSACTION_ID (same grain as Silver staging).
   No virtual invoice type rows. All measures on a single row.

   Steps:
     1. INSERT new fact rows from unprocessed Silver transactions
        - Apply sign: FL_IS_REFUND = 1 rows get negative amounts
     2. UPDATE existing rows when Silver data has changed (version bump)
     3. Apply EXCHANGE RATES:
        - Sales currency → GBP: Budget → Actual → BOE Spot → Override → Hardcode
        - Supplier currency → GBP
     4. Compute all BC (GBP) amount columns (TC × exchange rate)
     5. Compute derived commission measures
     6. Mark Silver rows as processed (FL_IS_PROCESSED_TO_GOLD = 1)
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L1_LoadFactSalesTransaction]
AS
BEGIN
    SET NOCOUNT ON;

    /*
    ============================================================
    STEP 1: INSERT new fact rows from unprocessed Silver rows
            Apply sign: confirmed = positive, refund = negative
    ============================================================
    */
    INSERT INTO [L1_FACT_SALES_TRANSACTION] (
        [ID_FACT_SALES],
        [CD_TRANSACTION_ID], [CD_SOURCE_SYSTEM],
        [CD_ORDER_ID], [CD_PRODUCT_ID], [ID_BOOKING],
        [ID_PRODUCT], [ID_SUPPLIER], [ID_AGENT],
        [CD_ORDER_STATUS], [FL_IS_REFUND],
        [DT_TRANSACTION], [DT_CREATED], [DT_DEPARTURE], [DT_CANCELLATION],
        [T_BOOKING_TYPE], [T_BOOKING_SOURCE], [T_PACKAGE_TYPE],
        [T_FISCAL_YEAR], [T_LEAD_PAX_NAME], [T_PAYMENT_METHOD], [CD_INVOICE_REFERENCE],
        [T_TICKET_TYPE], [T_PAX_TYPE], [NUM_TICKET_QUANTITY],
        [CD_TICKET_NUMBER], [T_MERCHANT_NAME], [T_SUPPLIER_ADMIN],
        [VL_VERSION],
        [CD_SALES_CURRENCY], [CD_SUPPLIER_CURRENCY],
        -- TC amounts (signed via FL_IS_REFUND)
        [AMT_SALE_PRICE_TC],
        [AMT_NET_SALE_PRICE_TC],
        [AMT_LIST_PRICE_TC],
        [AMT_DISTRIBUTOR_DISCOUNT_TC],
        [AMT_GENERAL_TAX_TC],
        [AMT_SUPPLIER_PRICE_TC],
        [AMT_NET_SUPPLIER_PRICE_TC],
        [AMT_DISTRIBUTOR_FEE_TC],
        [AMT_NET_DISTRIBUTOR_FEE_TC],
        [AMT_DISTRIBUTOR_TAX_TC],
        [AMT_RESELLER_FEE_TC],
        [AMT_MERCHANT_FEE_TC],
        [AMT_AFFILIATE_FEE_TC]
    )
    SELECT
        ISNULL((SELECT MAX(ID_FACT_SALES) FROM L1_FACT_SALES_TRANSACTION), 0)
            + ROW_NUMBER() OVER (ORDER BY st.ID_SALES_TRANSACTION),

        st.[CD_TRANSACTION_ID],
        'PRIO',
        bk.[CD_ORDER_ID],
        bk.[CD_PRODUCT_ID],
        bk.[ID_BOOKING],
        p.[ID_PRODUCT],
        s.[ID_SUPPLIER],
        a.[ID_AGENT],

        st.[CD_ORDER_STATUS],
        st.[FL_IS_REFUND],

        CAST(st.[DT_ORDER]           AS DATETIME2(0)),
        CAST(bk.[DT_CREATED]         AS DATE),
        CAST(bk.[DT_DEPARTURE]       AS DATE),
        CAST(bk.[DT_CANCELLATION]    AS DATE),

        bk.[T_BOOKING_TYPE],
        bk.[T_BOOKING_SOURCE],
        bk.[T_PACKAGE_TYPE],
        bk.[T_FISCAL_YEAR],
        bk.[T_LEAD_PAX_NAME],
        st.[T_PAYMENT_METHOD],
        st.[CD_INVOICE_REFERENCE],

        st.[T_TICKET_TYPE],
        CASE WHEN st.[T_TICKET_TYPE] IN ('Adult','Child') THEN st.[T_TICKET_TYPE] ELSE 'Other' END,
        -- Signed quantity
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[NUM_QUANTITY], 0)
             ELSE ISNULL(st.[NUM_QUANTITY], 0) END,

        st.[CD_TICKET_NUMBER],
        st.[T_MERCHANT_NAME],
        st.[T_SUPPLIER_ADMIN],
        st.[VL_VERSION],
        st.[CD_SALES_CURRENCY],
        st.[CD_SUPPLIER_CURRENCY],

        -- TC amounts: absolute value from Silver, sign applied here
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_SALE_PRICE],           0) ELSE ISNULL(st.[AMT_SALE_PRICE],           0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_NET_SALE_PRICE],        0) ELSE ISNULL(st.[AMT_NET_SALE_PRICE],        0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_LIST_PRICE],            0) ELSE ISNULL(st.[AMT_LIST_PRICE],            0) END,
        -- Distributor discount is always a reduction (0 or negative)
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN      ISNULL(st.[AMT_DISTRIBUTOR_DISCOUNT],  0)
             ELSE                              -1 * ISNULL(st.[AMT_DISTRIBUTOR_DISCOUNT], 0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_GENERAL_TAX],           0) ELSE ISNULL(st.[AMT_GENERAL_TAX],           0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_SUPPLIER_PRICE],        0) ELSE ISNULL(st.[AMT_SUPPLIER_PRICE],        0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_NET_SUPPLIER_PRICE],    0) ELSE ISNULL(st.[AMT_NET_SUPPLIER_PRICE],    0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_DISTRIBUTOR_FEE],       0) ELSE ISNULL(st.[AMT_DISTRIBUTOR_FEE],       0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_NET_DISTRIBUTOR_FEE],   0) ELSE ISNULL(st.[AMT_NET_DISTRIBUTOR_FEE],   0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_DISTRIBUTOR_TAX],       0) ELSE ISNULL(st.[AMT_DISTRIBUTOR_TAX],       0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_RESELLER_FEE],          0) ELSE ISNULL(st.[AMT_RESELLER_FEE],          0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_MERCHANT_FEE],          0) ELSE ISNULL(st.[AMT_MERCHANT_FEE],          0) END,
        CASE WHEN st.[FL_IS_REFUND] = 1 THEN -1 * ISNULL(st.[AMT_AFFILIATE_FEE],         0) ELSE ISNULL(st.[AMT_AFFILIATE_FEE],         0) END

    FROM [L0_SRG_SALES_TRANSACTION] st
    INNER JOIN [L0_SRG_BOOKING]  bk ON bk.[ID_BOOKING]  = st.[ID_BOOKING]
    INNER JOIN [L1_DIM_PRODUCT]  p  ON p.[ID_PRODUCT]   = st.[ID_PRODUCT]
    INNER JOIN [L1_DIM_SUPPLIER] s  ON s.[ID_SUPPLIER]  = st.[ID_SUPPLIER]
    INNER JOIN [L1_DIM_AGENT]    a  ON a.[ID_AGENT]     = st.[ID_AGENT]
    WHERE
        st.[FL_IS_PROCESSED_TO_GOLD] = 0
        AND NOT EXISTS (
            SELECT 1 FROM [L1_FACT_SALES_TRANSACTION] ex
            WHERE ex.[CD_TRANSACTION_ID] = st.[CD_TRANSACTION_ID]
              AND ex.[CD_SOURCE_SYSTEM]  = 'PRIO'
        );

    /*
    ============================================================
    STEP 2: UPDATE existing fact rows (changed version / status)
    ============================================================
    */
    UPDATE f
    SET
        f.[CD_ORDER_STATUS]          = st.[CD_ORDER_STATUS],
        f.[FL_IS_REFUND]             = st.[FL_IS_REFUND],
        f.[AMT_SALE_PRICE_TC]        = CASE WHEN st.[FL_IS_REFUND]=1 THEN -1*ISNULL(st.[AMT_SALE_PRICE],0)        ELSE ISNULL(st.[AMT_SALE_PRICE],0) END,
        f.[AMT_NET_SALE_PRICE_TC]    = CASE WHEN st.[FL_IS_REFUND]=1 THEN -1*ISNULL(st.[AMT_NET_SALE_PRICE],0)    ELSE ISNULL(st.[AMT_NET_SALE_PRICE],0) END,
        f.[AMT_SUPPLIER_PRICE_TC]    = CASE WHEN st.[FL_IS_REFUND]=1 THEN -1*ISNULL(st.[AMT_SUPPLIER_PRICE],0)    ELSE ISNULL(st.[AMT_SUPPLIER_PRICE],0) END,
        f.[AMT_NET_DISTRIBUTOR_FEE_TC]= CASE WHEN st.[FL_IS_REFUND]=1 THEN -1*ISNULL(st.[AMT_NET_DISTRIBUTOR_FEE],0) ELSE ISNULL(st.[AMT_NET_DISTRIBUTOR_FEE],0) END,
        f.[AMT_DISTRIBUTOR_TAX_TC]   = CASE WHEN st.[FL_IS_REFUND]=1 THEN -1*ISNULL(st.[AMT_DISTRIBUTOR_TAX],0)  ELSE ISNULL(st.[AMT_DISTRIBUTOR_TAX],0) END,
        f.[NUM_TICKET_QUANTITY]      = CASE WHEN st.[FL_IS_REFUND]=1 THEN -1*ISNULL(st.[NUM_QUANTITY],0)          ELSE ISNULL(st.[NUM_QUANTITY],0) END,
        f.[VL_VERSION]               = st.[VL_VERSION],
        f.[CD_SALES_CURRENCY]        = st.[CD_SALES_CURRENCY],
        f.[CD_SUPPLIER_CURRENCY]     = st.[CD_SUPPLIER_CURRENCY],
        f.[DT_TRANSACTION]           = CAST(st.[DT_ORDER] AS DATETIME2(0)),
        -- Reset exchange rate / BC amounts so they are recalculated below
        f.[VL_SALES_EXCHANGE_RATE]   = NULL,
        f.[VL_SUPPLIER_EXCHANGE_RATE]= NULL,
        f.[CD_EXCHANGE_RATE_TYPE]    = NULL,
        f.[DT_LAST_UPDATED]          = SYSDATETIME()
    FROM [L1_FACT_SALES_TRANSACTION] f
    INNER JOIN [L0_SRG_SALES_TRANSACTION] st
        ON st.[CD_TRANSACTION_ID] = f.[CD_TRANSACTION_ID]
        AND st.[CD_SOURCE]        = 'PRIO'
    WHERE st.[FL_IS_PROCESSED_TO_GOLD] = 0;

    /*
    ============================================================
    STEP 3: Apply Exchange Rates — Sales Currency → GBP
    Priority: GBP pass-through → Budget → Actual → BOE Spot → Override → Hardcode
    ============================================================
    */

    -- GBP: no conversion needed
    UPDATE [L1_FACT_SALES_TRANSACTION]
    SET [VL_SALES_EXCHANGE_RATE] = 1.0,
        [CD_EXCHANGE_RATE_TYPE]  = 'GBP'
    WHERE [CD_SALES_CURRENCY] IN ('GBP', 'GBP(T)')
      AND [VL_SALES_EXCHANGE_RATE] IS NULL;

    -- Budget rate: future departures (TY = same year, NY = next year, FY = 2+ years out)
    UPDATE f
    SET
        f.[VL_SALES_EXCHANGE_RATE] = CASE
            WHEN YEAR(f.[DT_DEPARTURE]) = YEAR(f.[DT_CREATED])
                THEN (SELECT MAX(er.[VL_RATE_TY]) FROM [L0_EXCHANGE_RATES] er
                      WHERE CAST(f.[DT_CREATED] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM] AND er.[DT_EFFECTIVE_TO]
                        AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE]
                        AND er.[CD_RATE_TYPE] = 'Budget')
            WHEN YEAR(f.[DT_DEPARTURE]) = YEAR(f.[DT_CREATED]) + 1
                THEN (SELECT MAX(er.[VL_RATE_NY]) FROM [L0_EXCHANGE_RATES] er
                      WHERE CAST(f.[DT_CREATED] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM] AND er.[DT_EFFECTIVE_TO]
                        AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE]
                        AND er.[CD_RATE_TYPE] = 'Budget')
            ELSE    (SELECT MAX(er.[VL_RATE_FY]) FROM [L0_EXCHANGE_RATES] er
                     WHERE CAST(f.[DT_CREATED] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM] AND er.[DT_EFFECTIVE_TO]
                       AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE]
                       AND er.[CD_RATE_TYPE] = 'Budget')
        END,
        f.[CD_EXCHANGE_RATE_TYPE] = 'Budget'
    FROM [L1_FACT_SALES_TRANSACTION] f
    WHERE f.[DT_DEPARTURE] >= CAST(GETDATE() AS DATE)
      AND f.[CD_SALES_CURRENCY] NOT IN ('GBP', 'GBP(T)')
      AND f.[VL_SALES_EXCHANGE_RATE] IS NULL;

    -- Actual rate: past departures (post-2022)
    UPDATE f
    SET
        f.[VL_SALES_EXCHANGE_RATE] = (
            SELECT MAX(er.[VL_EXCHANGE_RATE]) FROM [L0_EXCHANGE_RATES] er
            WHERE CAST(f.[DT_DEPARTURE] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM]
                                                      AND ISNULL(er.[DT_EFFECTIVE_TO], '9999-12-31')
              AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE]
              AND er.[CD_RATE_TYPE] = 'Actual'
              AND er.[FL_IS_ACTIVE] = 1
        ),
        f.[CD_EXCHANGE_RATE_TYPE] = 'Actual'
    FROM [L1_FACT_SALES_TRANSACTION] f
    WHERE f.[DT_DEPARTURE] < CAST(GETDATE() AS DATE)
      AND YEAR(f.[DT_DEPARTURE]) > 2022
      AND f.[CD_SALES_CURRENCY] NOT IN ('GBP', 'GBP(T)')
      AND f.[VL_SALES_EXCHANGE_RATE] IS NULL;

    -- BOE Spot rate: fallback when no budget or actual rate found
    UPDATE f
    SET
        f.[VL_SALES_EXCHANGE_RATE] = er.[VL_EXCHANGE_RATE],
        f.[CD_EXCHANGE_RATE_TYPE]  = 'BOE_Spot'
    FROM [L1_FACT_SALES_TRANSACTION] f
    INNER JOIN [L0_EXCHANGE_RATES] er
        ON er.[CD_CURRENCY_CODE] = f.[CD_SALES_CURRENCY]
        AND CAST(f.[DT_CREATED] AS DATE) = er.[DT_EFFECTIVE_FROM]
        AND er.[CD_RATE_TYPE] = 'BOE_Spot'
    WHERE f.[CD_SALES_CURRENCY] NOT IN ('GBP', 'GBP(T)')
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
        ON f.[DT_DEPARTURE] BETWEEN er.[DT_TRAVEL_START]  AND er.[DT_TRAVEL_END]
        AND f.[DT_CREATED]  BETWEEN er.[DT_BOOKING_START] AND er.[DT_BOOKING_END]
        AND f.[CD_SALES_CURRENCY] = er.[CD_CURRENCY_CODE]
        AND er.[CD_RATE_TYPE] = 'Override'
        AND p.[CD_PRODUCT_ID]     IN (SELECT value FROM STRING_SPLIT(er.[CD_PRODUCT_IDS], ','))
        AND a.[CD_DISTRIBUTOR_ID] IN (SELECT value FROM STRING_SPLIT(er.[CD_AGENT_IDS], ','))
    WHERE f.[CD_SALES_CURRENCY] NOT IN ('GBP', 'GBP(T)');

    -- Historical hardcode: 2022 USD (preserved from legacy system)
    UPDATE [L1_FACT_SALES_TRANSACTION]
    SET [VL_SALES_EXCHANGE_RATE] = 1.27,
        [CD_EXCHANGE_RATE_TYPE]  = 'Historical_Hardcode'
    WHERE [CD_SALES_CURRENCY] = 'USD'
      AND YEAR([DT_DEPARTURE]) = 2022
      AND [DT_DEPARTURE] <= GETDATE()
      AND [VL_SALES_EXCHANGE_RATE] IS NULL;

    -- Supplier exchange rate: same logic, applied to supplier currency
    UPDATE f
    SET f.[VL_SUPPLIER_EXCHANGE_RATE] = CASE
        WHEN f.[CD_SUPPLIER_CURRENCY] IN ('GBP', 'GBP(T)') THEN 1.0
        WHEN f.[CD_SUPPLIER_CURRENCY] = f.[CD_SALES_CURRENCY] THEN f.[VL_SALES_EXCHANGE_RATE]
        ELSE (
            SELECT MAX(er.[VL_EXCHANGE_RATE]) FROM [L0_EXCHANGE_RATES] er
            WHERE CAST(f.[DT_DEPARTURE] AS DATE) BETWEEN er.[DT_EFFECTIVE_FROM]
                                                      AND ISNULL(er.[DT_EFFECTIVE_TO], '9999-12-31')
              AND f.[CD_SUPPLIER_CURRENCY] = er.[CD_CURRENCY_CODE]
              AND er.[CD_RATE_TYPE] IN ('Actual','BOE_Spot')
              AND er.[FL_IS_ACTIVE] = 1
        )
    END
    FROM [L1_FACT_SALES_TRANSACTION] f
    WHERE f.[VL_SUPPLIER_EXCHANGE_RATE] IS NULL;

    /*
    ============================================================
    STEP 4: Compute all base currency (GBP) amounts
    ============================================================
    */
    UPDATE [L1_FACT_SALES_TRANSACTION]
    SET
        [AMT_SALE_PRICE_BC]           = [AMT_SALE_PRICE_TC]           * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_NET_SALE_PRICE_BC]       = [AMT_NET_SALE_PRICE_TC]       * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_LIST_PRICE_BC]           = [AMT_LIST_PRICE_TC]           * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_DISTRIBUTOR_DISCOUNT_BC] = [AMT_DISTRIBUTOR_DISCOUNT_TC] * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_GENERAL_TAX_BC]          = [AMT_GENERAL_TAX_TC]          * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_SUPPLIER_PRICE_BC]       = [AMT_SUPPLIER_PRICE_TC]       * ISNULL([VL_SUPPLIER_EXCHANGE_RATE], [VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_NET_SUPPLIER_PRICE_BC]   = [AMT_NET_SUPPLIER_PRICE_TC]   * ISNULL([VL_SUPPLIER_EXCHANGE_RATE], [VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_DISTRIBUTOR_FEE_BC]      = [AMT_DISTRIBUTOR_FEE_TC]      * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_NET_DISTRIBUTOR_FEE_BC]  = [AMT_NET_DISTRIBUTOR_FEE_TC]  * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_DISTRIBUTOR_TAX_BC]      = [AMT_DISTRIBUTOR_TAX_TC]      * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_RESELLER_FEE_BC]         = [AMT_RESELLER_FEE_TC]         * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_MERCHANT_FEE_BC]         = [AMT_MERCHANT_FEE_TC]         * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0),
        [AMT_AFFILIATE_FEE_BC]        = [AMT_AFFILIATE_FEE_TC]        * ISNULL([VL_SALES_EXCHANGE_RATE], 1.0)
    WHERE [VL_SALES_EXCHANGE_RATE] IS NOT NULL
       OR [CD_SALES_CURRENCY] IN ('GBP', 'GBP(T)');

    /*
    ============================================================
    STEP 5: Compute derived commission measures (GBP)
    ============================================================
    */
    UPDATE [L1_FACT_SALES_TRANSACTION]
    SET
        -- Net commission owed to agent
        [AMT_AGENT_COMMISSION_BC]      = [AMT_NET_DISTRIBUTOR_FEE_BC],
        -- VAT charged on that commission
        [AMT_VAT_ON_COMMISSION_BC]     = [AMT_DISTRIBUTOR_TAX_BC],
        -- Total commission cost = agent commission + VAT
        [AMT_TOTAL_COMMISSION_COST_BC] = ISNULL([AMT_NET_DISTRIBUTOR_FEE_BC], 0)
                                       + ISNULL([AMT_DISTRIBUTOR_TAX_BC], 0);

    /*
    ============================================================
    STEP 6: Mark Silver rows as processed
    ============================================================
    */
    UPDATE [L0_SRG_SALES_TRANSACTION]
    SET [FL_IS_PROCESSED_TO_GOLD] = 1,
        [DT_LAST_UPDATED]         = SYSDATETIME()
    WHERE [FL_IS_PROCESSED_TO_GOLD] = 0;

END;
