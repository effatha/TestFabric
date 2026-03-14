/*
================================================================================
 Procedure: usp_L0_MergeSalesTransactions
 Layer: Silver (L0)
 Source: L0_PRIO_SALES_TRANSACTION (unprocessed), L0_SRG_BOOKING, L0_SRG_PRODUCT,
         L0_SRG_SUPPLIER, L0_SRG_AGENT
 Target: L0_SRG_SALES_TRANSACTION
================================================================================
 Granularity: ONE ROW per CD_TRANSACTION_ID (same as staging).
              No invoice type fan-out. All amounts as absolute values.
              FL_IS_REFUND = 1 for refund / cancellation transactions.

 Special agent handling:
   - Distributors 49404, 4365, 48321, 54034: USD sales currency override
   - Distributors 49404, 4365: AMT_NET_DISTRIBUTOR_FEE += NET_RESELLER_FEE
   - Distributor 48749 (staff discount): AMT_NET_DISTRIBUTOR_FEE = 0
   - Net agents:   sale price reduced by commission; commission zeroed
   - CostPlus:     sale price = local_currency_price × (1 + agent_markup); commission zeroed
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L0_MergeSalesTransactions]
AS
BEGIN
    SET NOCOUNT ON;

    /*
    ============================================================
    STEP 1: INSERT new transaction lines not yet in Silver SRG
    ============================================================
    */
    INSERT INTO [L0_SRG_SALES_TRANSACTION] (
        [ID_SALES_TRANSACTION],
        [CD_TRANSACTION_ID], [CD_SOURCE],
        [ID_BOOKING], [ID_PRODUCT], [ID_SUPPLIER], [ID_AGENT],
        [CD_ORDER_STATUS], [FL_IS_REFUND],
        [AMT_SALE_PRICE],
        [AMT_NET_SALE_PRICE],
        [AMT_LIST_PRICE],
        [AMT_DISTRIBUTOR_DISCOUNT],
        [AMT_GENERAL_TAX],
        [AMT_SUPPLIER_PRICE],
        [AMT_NET_SUPPLIER_PRICE],
        [AMT_DISTRIBUTOR_FEE],
        [AMT_NET_DISTRIBUTOR_FEE],
        [AMT_DISTRIBUTOR_TAX],
        [AMT_RESELLER_FEE],
        [AMT_MERCHANT_FEE],
        [AMT_AFFILIATE_FEE],
        [CD_SALES_CURRENCY], [CD_SUPPLIER_CURRENCY],
        [T_TICKET_TYPE], [NUM_QUANTITY], [CD_TICKET_NUMBER],
        [T_MERCHANT_NAME], [T_SUPPLIER_ADMIN],
        [T_PAYMENT_METHOD], [CD_INVOICE_REFERENCE],
        [VL_VERSION], [DT_ORDER]
    )
    SELECT
        ISNULL((SELECT MAX(ID_SALES_TRANSACTION) FROM L0_SRG_SALES_TRANSACTION), 0)
            + ROW_NUMBER() OVER (ORDER BY t.CD_TRANSACTION_ID),

        REPLACE(t.CD_TRANSACTION_ID, '-', ''),
        'PRIO',

        bk.ID_BOOKING,
        ISNULL(p.ID_PRODUCT, 0),      -- 0 for discount lines (no product)
        ISNULL(s.ID_SUPPLIER, 0),     -- 0 for reprice / discount lines
        a.ID_AGENT,

        t.CD_INVOICE_STATUS,
        -- FL_IS_REFUND: refund if sale price is negative, or status is Refunded/Rebooked
        CASE WHEN t.AMT_SALE_PRICE < 0
                  OR t.CD_INVOICE_STATUS IN ('Refunded', 'Rebooked')
             THEN 1 ELSE 0 END,

        ABS(t.AMT_SALE_PRICE),
        ABS(ISNULL(t.AMT_NET_SALE_PRICE, t.AMT_SALE_PRICE)),
        ABS(ISNULL(t.AMT_LIST_PRICE, t.AMT_SALE_PRICE)),
        ABS(ISNULL(t.AMT_DISTRIBUTOR_DISCOUNT, 0)),
        ABS(ISNULL(t.AMT_GENERAL_TAX, 0)),
        -- Supplier buy rate: prefer Local_Currency_Price; fall back to Supplier_Price
        ABS(ISNULL(t.AMT_LOCAL_CURRENCY_PRICE, ISNULL(t.AMT_SUPPLIER_PRICE, 0))),
        ABS(ISNULL(t.AMT_LOCAL_CURRENCY_NET_PRICE, ISNULL(t.AMT_NET_SUPPLIER_PRICE, 0))),
        ABS(ISNULL(t.AMT_DISTRIBUTOR_FEE, 0)),
        -- Net commission: specific distributors combine reseller fee
        ABS(CASE
            WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365)
                THEN ISNULL(t.AMT_NET_DISTRIBUTOR_FEE, 0) + ISNULL(t.AMT_NET_RESELLER_FEE, 0)
            WHEN t.CD_DISTRIBUTOR_ID = 48749
                THEN 0                -- Staff discount: no commission
            ELSE ISNULL(t.AMT_NET_DISTRIBUTOR_FEE, 0)
        END),
        ABS(ISNULL(t.AMT_DISTRIBUTOR_TAX, 0)),
        ABS(ISNULL(t.AMT_RESELLER_FEE, 0)),
        ABS(ISNULL(t.AMT_MERCHANT_FEE, 0)),
        ABS(ISNULL(t.AMT_AFFILIATE_FEE, 0)),

        -- Currency override for specific USD distributors
        CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365, 48321, 54034) THEN 'USD'
             ELSE t.CD_SALES_CURRENCY END,
        t.CD_SUPPLIER_CURRENCY,

        t.T_PRODUCT_TYPE,             -- Adult / Child / etc.
        ABS(ISNULL(t.NUM_PCS, 0)),
        t.CD_PASS_NO,
        t.T_MERCHANT_NAME,
        t.T_FLAG_VALUE,               -- Actual Supplier (Flag_Name = 'Actual Supplier')
        t.T_PAYMENT_METHOD,
        t.CD_PSP_REFERENCE,
        TRY_CAST(t.CD_TRANSACTION_VERSION AS FLOAT),
        -- Use earlier of booking created date vs transaction datetime
        CASE WHEN bk.DT_CREATED > t.DT_TRANSACTION THEN bk.DT_CREATED ELSE t.DT_TRANSACTION END

    FROM [L0_PRIO_SALES_TRANSACTION] t
    INNER JOIN [L0_SRG_BOOKING]  bk ON bk.CD_ORDER_ID   = t.CD_ORDER_ID
                                    AND bk.CD_PRODUCT_ID = ISNULL(t.CD_PRODUCT_ID, 0)
    LEFT JOIN  [L0_SRG_PRODUCT]  p  ON p.CD_PRODUCT_ID  = t.CD_PRODUCT_ID
                                    AND p.CD_SOURCE      = 'PRIO'
    LEFT JOIN  [L0_SRG_SUPPLIER] s  ON s.CD_SUPPLIER_ID = t.CD_SUPPLIER_ID
                                    AND s.CD_SOURCE      = 'PRIO'
    INNER JOIN [L0_SRG_AGENT]    a  ON a.CD_DISTRIBUTOR_ID = t.CD_DISTRIBUTOR_ID
                                    AND a.CD_SOURCE         = 'PRIO'
    WHERE
        t.FL_IS_PROCESSED = 0
        AND t.CD_TRANSACTION_VERSION <> ''
        AND NOT EXISTS (
            SELECT 1 FROM [L0_SRG_SALES_TRANSACTION] ex
            WHERE ex.CD_TRANSACTION_ID = REPLACE(t.CD_TRANSACTION_ID, '-', '')
              AND ex.CD_SOURCE = 'PRIO'
        );

    /*
    ============================================================
    STEP 2: UPDATE existing transactions that have new versions
    ============================================================
    */
    UPDATE st
    SET
        st.[AMT_SALE_PRICE]          = ABS(t.AMT_SALE_PRICE),
        st.[AMT_NET_SALE_PRICE]      = ABS(ISNULL(t.AMT_NET_SALE_PRICE, t.AMT_SALE_PRICE)),
        st.[AMT_LIST_PRICE]          = ABS(ISNULL(t.AMT_LIST_PRICE, t.AMT_SALE_PRICE)),
        st.[AMT_DISTRIBUTOR_DISCOUNT]= ABS(ISNULL(t.AMT_DISTRIBUTOR_DISCOUNT, 0)),
        st.[AMT_GENERAL_TAX]         = ABS(ISNULL(t.AMT_GENERAL_TAX, 0)),
        st.[AMT_SUPPLIER_PRICE]      = ABS(ISNULL(t.AMT_LOCAL_CURRENCY_PRICE, ISNULL(t.AMT_SUPPLIER_PRICE, 0))),
        st.[AMT_NET_SUPPLIER_PRICE]  = ABS(ISNULL(t.AMT_LOCAL_CURRENCY_NET_PRICE, ISNULL(t.AMT_NET_SUPPLIER_PRICE, 0))),
        st.[AMT_NET_DISTRIBUTOR_FEE] = ABS(CASE
            WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365)
                THEN ISNULL(t.AMT_NET_DISTRIBUTOR_FEE, 0) + ISNULL(t.AMT_NET_RESELLER_FEE, 0)
            WHEN t.CD_DISTRIBUTOR_ID = 48749
                THEN 0
            ELSE ISNULL(t.AMT_NET_DISTRIBUTOR_FEE, 0)
        END),
        st.[AMT_DISTRIBUTOR_TAX]     = ABS(ISNULL(t.AMT_DISTRIBUTOR_TAX, 0)),
        st.[CD_ORDER_STATUS]         = t.CD_INVOICE_STATUS,
        st.[FL_IS_REFUND]            = CASE WHEN t.AMT_SALE_PRICE < 0
                                                  OR t.CD_INVOICE_STATUS IN ('Refunded','Rebooked')
                                            THEN 1 ELSE 0 END,
        st.[VL_VERSION]              = TRY_CAST(t.CD_TRANSACTION_VERSION AS FLOAT),
        st.[CD_SALES_CURRENCY]       = CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404,4365,48321,54034) THEN 'USD'
                                            ELSE t.CD_SALES_CURRENCY END,
        st.[CD_SUPPLIER_CURRENCY]    = t.CD_SUPPLIER_CURRENCY,
        st.[DT_ORDER]                = CASE WHEN bk.DT_CREATED > t.DT_TRANSACTION
                                            THEN bk.DT_CREATED ELSE t.DT_TRANSACTION END,
        st.[DT_LAST_UPDATED]         = SYSDATETIME(),
        st.[FL_IS_PROCESSED_TO_GOLD] = 0    -- Reset so Gold picks up the change
    FROM [L0_PRIO_SALES_TRANSACTION] t
    INNER JOIN [L0_SRG_BOOKING]          bk ON bk.CD_ORDER_ID = t.CD_ORDER_ID
                                            AND bk.CD_PRODUCT_ID = ISNULL(t.CD_PRODUCT_ID, 0)
    INNER JOIN [L0_SRG_SALES_TRANSACTION] st
        ON st.CD_TRANSACTION_ID = REPLACE(t.CD_TRANSACTION_ID, '-', '')
        AND st.CD_SOURCE = 'PRIO'
    WHERE t.FL_IS_PROCESSED = 0;

    /*
    ============================================================
    STEP 3: Net agent adjustment
    Revenue = Sale Price - Commission (commission is already embedded in sale price)
    ============================================================
    */
    UPDATE st
    SET
        st.[AMT_SALE_PRICE]          = st.AMT_SALE_PRICE     - st.AMT_NET_DISTRIBUTOR_FEE,
        st.[AMT_NET_SALE_PRICE]      = st.AMT_NET_SALE_PRICE - st.AMT_NET_DISTRIBUTOR_FEE,
        st.[AMT_NET_DISTRIBUTOR_FEE] = 0,
        st.[AMT_DISTRIBUTOR_FEE]     = 0
    FROM [L0_SRG_SALES_TRANSACTION] st
    INNER JOIN [L0_SRG_AGENT] a ON a.ID_AGENT = st.ID_AGENT
    WHERE
        a.FL_IS_NET_AGENT = 1
        AND st.AMT_SALE_PRICE <> 0
        AND st.FL_IS_PROCESSED_TO_GOLD = 0;

    /*
    ============================================================
    STEP 4: CostPlus agent adjustment
    Sale Price = Local Currency Price × (1 + Agent Markup)
    Commission zeroed (margin is embedded in the recalculated price)
    ============================================================
    */
    UPDATE st
    SET
        st.[AMT_SALE_PRICE]          = t.AMT_LOCAL_CURRENCY_PRICE * (1 + a.VL_AGENT_MARKUP),
        st.[AMT_NET_SALE_PRICE]      = t.AMT_LOCAL_CURRENCY_PRICE * (1 + a.VL_AGENT_MARKUP),
        st.[AMT_NET_DISTRIBUTOR_FEE] = 0,
        st.[AMT_DISTRIBUTOR_FEE]     = 0,
        st.[CD_SALES_CURRENCY]       = st.CD_SUPPLIER_CURRENCY
    FROM [L0_SRG_SALES_TRANSACTION] st
    INNER JOIN [L0_SRG_AGENT] a ON a.ID_AGENT = st.ID_AGENT
                                AND a.T_DISTRIBUTOR_TYPE = 'CostPlus'
    INNER JOIN [L0_PRIO_SALES_TRANSACTION] t
        ON REPLACE(t.CD_TRANSACTION_ID, '-', '') = st.CD_TRANSACTION_ID
        AND t.FL_IS_PROCESSED = 0
    WHERE
        st.AMT_SALE_PRICE <> 0
        AND st.FL_IS_PROCESSED_TO_GOLD = 0;

    /*
    ============================================================
    STEP 5: Mark source rows as processed
    ============================================================
    */
    UPDATE [L0_PRIO_SALES_TRANSACTION]
        SET [FL_IS_PROCESSED] = 1,
            [DT_LAST_UPDATE]  = SYSDATETIME()
    WHERE [FL_IS_PROCESSED] = 0;

END;
