/*
================================================================================
 Procedure: usp_L0_MergeSalesTransactions
 Layer: Silver (L0)
 Source: L0_PRIO_SALES_TRANSACTION (unprocessed), L0_SRG_BOOKING, L0_SRG_PRODUCT,
         L0_SRG_SUPPLIER, L0_SRG_AGENT, L0_REF_INVOICE_STATUS
 Target: L0_SRG_SALES_TRANSACTION
 Old equivalent: usp_ProcessPrioTransactions + usp_ProcessAgentCommissions
================================================================================
 Purpose:
   Loads individual sales transaction lines into the L0_SRG_SALES_TRANSACTION table.
   Three categories of lines are created per source transaction:
     1. TICKET lines (Product_ID > 0, Supplier_ID > 0) - Revenue / Refund lines
     2. REPRICE lines (Product_ID > 0, Supplier_ID = 0) - Reprice adjustments
     3. DISCOUNT lines (Product_ID = 0) - Discount voucher lines
   Virtual commission lines are created separately in usp_L0_LoadAgentCommissions.

   Special agent handling (mirrors old system):
   - Specific distributor IDs (49404, 4365, 48321, 54034) have USD currency override
   - Net agents: commission subtracted from RevenueAmount
   - CostPlus agents: RevenueAmount = LocalCurrencyPrice × (1 + AgentMarkup)
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L0_MergeSalesTransactions]
AS
BEGIN
    SET NOCOUNT ON;

    /*
    ============================================================
    STEP 1: INSERT new TICKET transaction lines (Product_ID > 0, Supplier_ID > 0)
    ============================================================
    */
    INSERT INTO [L0_SRG_SALES_TRANSACTION] (
        [CD_TRANSACTION_ID], [CD_INVOICE_TYPE], [CD_SOURCE],
        [ID_BOOKING], [ID_PRODUCT], [ID_SUPPLIER], [ID_AGENT],
        [CD_INVOICE_TID], [CD_INVOICE_SID], [CD_INVOICE_CATEGORY],
        [T_TYPE_AMOUNT], [CD_ORDER_STATUS],
        [AMT_REVENUE], [AMT_SUPPLIER_PRICE], [AMT_COMMISSION], [AMT_REVENUE_VAT],
        [CD_SALES_CURRENCY], [CD_SUPPLIER_CURRENCY],
        [T_TICKET_TYPE], [NUM_QUANTITY], [CD_TICKET_NUMBER],
        [T_MERCHANT_NAME], [T_SUPPLIER_ADMIN],
        [T_PAYMENT_METHOD], [CD_INVOICE_REFERENCE],
        [VL_VERSION], [DT_ORDER]
    )
    SELECT DISTINCT
        REPLACE(t.CD_TRANSACTION_ID, '-', ''),
        inv.T_INVOICE_TYPE,
        'PRIO',
        b.ID_BOOKING,
        p.ID_PRODUCT,
        s.ID_SUPPLIER,
        a.ID_AGENT,
        inv.CD_INVOICE_TID,
        inv.CD_INVOICE_SID,
        CASE WHEN bk.T_BOOKING_TYPE = 'Trade' THEN 4 ELSE 2 END,  -- 4=Agent, 2=Retail

        -- TypeAmount: Revenue lines from Prio come as Debit unless price < 0
        CASE WHEN inv.T_INVOICE_TYPE = 'Revenue' AND t.AMT_SALE_PRICE < 0 THEN 'C' ELSE inv.CD_TYPE_AMOUNT END,

        t.CD_INVOICE_STATUS,
        ABS(t.AMT_SALE_PRICE),
        t.AMT_LOCAL_CURRENCY_PRICE,  -- Supplier buy rate (local currency price)

        -- Commission: specific distributors add reseller fee to distributor fee
        CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365)
             THEN ISNULL(t.AMT_NET_DISTRIBUTOR_FEE, 0) + ISNULL(t.AMT_NET_RESELLER_FEE, 0)
             ELSE t.AMT_NET_DISTRIBUTOR_FEE
        END,

        t.AMT_GENERAL_TAX,  -- VAT / General tax

        -- Currency override for specific USD distributors
        CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365, 48321, 54034) THEN 'USD'
             ELSE t.CD_SALES_CURRENCY END,
        t.CD_SUPPLIER_CURRENCY,

        t.T_PRODUCT_TYPE,  -- Adult / Child / etc.
        ABS(t.NUM_PCS),
        t.CD_PASS_NO,
        t.T_MERCHANT_NAME,
        t.T_FLAG_VALUE,    -- Actual Supplier from Flag_Name = 'Actual Supplier'
        t.T_PAYMENT_METHOD,
        t.CD_PSP_REFERENCE,
        TRY_CAST(t.CD_TRANSACTION_VERSION AS FLOAT),
        -- Order date: use earlier of booking created or transaction datetime
        CASE WHEN bk.DT_CREATED > t.DT_TRANSACTION THEN bk.DT_CREATED ELSE t.DT_TRANSACTION END

    FROM [L0_PRIO_SALES_TRANSACTION] t
    INNER JOIN [L0_SRG_BOOKING]     bk ON bk.CD_ORDER_ID = t.CD_ORDER_ID AND bk.CD_PRODUCT_ID = t.CD_PRODUCT_ID
    INNER JOIN [L0_SRG_PRODUCT]     p  ON p.CD_PRODUCT_ID = t.CD_PRODUCT_ID AND p.CD_SOURCE = 'PRIO'
    INNER JOIN [L0_SRG_SUPPLIER]    s  ON s.CD_SUPPLIER_ID = t.CD_SUPPLIER_ID AND s.CD_SOURCE = 'PRIO'
    INNER JOIN [L0_SRG_AGENT]       a  ON a.CD_DISTRIBUTOR_ID = t.CD_DISTRIBUTOR_ID AND a.CD_SOURCE = 'PRIO'
    INNER JOIN [L0_REF_INVOICE_STATUS] inv ON inv.CD_INVOICE_STATUS = t.CD_INVOICE_STATUS
    LEFT JOIN  [L0_SRG_SALES_TRANSACTION] ex
        ON ex.CD_TRANSACTION_ID = REPLACE(t.CD_TRANSACTION_ID, '-', '')
        AND ex.CD_INVOICE_TYPE  = inv.T_INVOICE_TYPE
    WHERE
        t.FL_IS_PROCESSED = 0
        AND ex.ID_SALES_TRANSACTION IS NULL  -- Not yet loaded
        AND t.CD_TRANSACTION_VERSION <> ''
        AND t.CD_PRODUCT_ID > 0
        AND t.CD_SUPPLIER_ID > 0;

    /*
    ============================================================
    STEP 2: INSERT REPRICE lines (Product_ID > 0, Supplier_ID = 0)
    ============================================================
    */
    INSERT INTO [L0_SRG_SALES_TRANSACTION] (
        [CD_TRANSACTION_ID], [CD_INVOICE_TYPE], [CD_SOURCE],
        [ID_BOOKING], [ID_PRODUCT], [ID_SUPPLIER], [ID_AGENT],
        [CD_INVOICE_CATEGORY], [T_TYPE_AMOUNT], [CD_ORDER_STATUS],
        [AMT_REVENUE], [AMT_SUPPLIER_PRICE], [AMT_COMMISSION],
        [CD_SALES_CURRENCY], [CD_SUPPLIER_CURRENCY],
        [T_TICKET_TYPE], [NUM_QUANTITY], [VL_VERSION], [DT_ORDER]
    )
    SELECT DISTINCT
        REPLACE(t.CD_TRANSACTION_ID, '-', ''),
        inv.T_INVOICE_TYPE,
        'PRIO',
        b.ID_BOOKING,
        p.ID_PRODUCT,
        s.ID_SUPPLIER,
        a.ID_AGENT,
        CASE WHEN bk.T_BOOKING_TYPE = 'Trade' THEN 4 ELSE 2 END,
        CASE WHEN t.AMT_SALE_PRICE < 0 THEN 'C' ELSE 'D' END,
        t.CD_INVOICE_STATUS,
        ABS(t.AMT_SALE_PRICE),
        t.AMT_LOCAL_CURRENCY_PRICE,
        CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365)
             THEN ISNULL(t.AMT_NET_DISTRIBUTOR_FEE, 0) + ISNULL(t.AMT_NET_RESELLER_FEE, 0)
             ELSE t.AMT_NET_DISTRIBUTOR_FEE END,
        CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365, 48321, 54034) THEN 'USD' ELSE t.CD_SALES_CURRENCY END,
        t.CD_SUPPLIER_CURRENCY,
        t.T_PRODUCT_TYPE,
        ABS(t.NUM_PCS),
        TRY_CAST(t.CD_TRANSACTION_VERSION AS FLOAT),
        CASE WHEN bk.DT_CREATED > t.DT_TRANSACTION THEN bk.DT_CREATED ELSE t.DT_TRANSACTION END
    FROM [L0_PRIO_SALES_TRANSACTION] t
    INNER JOIN [L0_SRG_BOOKING]     bk ON bk.CD_ORDER_ID = t.CD_ORDER_ID AND bk.CD_PRODUCT_ID = t.CD_PRODUCT_ID
    INNER JOIN [L0_SRG_PRODUCT]     p  ON p.CD_PRODUCT_ID = t.CD_PRODUCT_ID AND p.CD_SOURCE = 'PRIO'
    INNER JOIN [L0_SRG_SUPPLIER]    s  ON s.ID_SUPPLIER = p.ID_SUPPLIER
    INNER JOIN [L0_SRG_AGENT]       a  ON a.CD_DISTRIBUTOR_ID = t.CD_DISTRIBUTOR_ID AND a.CD_SOURCE = 'PRIO'
    INNER JOIN [L0_REF_INVOICE_STATUS] inv ON inv.CD_INVOICE_STATUS = t.CD_INVOICE_STATUS
    LEFT JOIN  [L0_SRG_SALES_TRANSACTION] ex
        ON ex.CD_TRANSACTION_ID = REPLACE(t.CD_TRANSACTION_ID, '-', '')
        AND ex.CD_INVOICE_TYPE = inv.T_INVOICE_TYPE
    WHERE
        t.FL_IS_PROCESSED = 0
        AND ex.ID_SALES_TRANSACTION IS NULL
        AND t.CD_TRANSACTION_VERSION <> ''
        AND t.CD_PRODUCT_ID > 0
        AND ISNULL(t.CD_SUPPLIER_ID, 0) = 0;  -- Supplier = 0 = reprice

    /*
    ============================================================
    STEP 3: INSERT DISCOUNT lines (Product_ID = 0)
    ============================================================
    */
    INSERT INTO [L0_SRG_SALES_TRANSACTION] (
        [CD_TRANSACTION_ID], [CD_INVOICE_TYPE], [CD_SOURCE],
        [ID_BOOKING], [ID_AGENT],
        [CD_INVOICE_CATEGORY], [T_TYPE_AMOUNT], [CD_ORDER_STATUS],
        [AMT_REVENUE], [AMT_COMMISSION],
        [CD_SALES_CURRENCY], [T_TICKET_TYPE], [NUM_QUANTITY],
        [VL_VERSION], [DT_ORDER]
    )
    SELECT DISTINCT
        REPLACE(t.CD_TRANSACTION_ID, '-', ''),
        'Discounts',
        'PRIO',
        b.ID_BOOKING,
        a.ID_AGENT,
        CASE WHEN bk.T_BOOKING_TYPE = 'Trade' THEN 4 ELSE 2 END,
        CASE WHEN t.AMT_SALE_PRICE >= 0 THEN 'D' ELSE 'C' END,
        t.CD_INVOICE_STATUS,
        ABS(t.AMT_SALE_PRICE),
        -- Commission for discount lines: staff discount gets 0
        CASE
            WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365)
                THEN ISNULL(t.AMT_NET_DISTRIBUTOR_FEE, 0) + ISNULL(t.AMT_NET_RESELLER_FEE, 0)
            WHEN t.CD_DISTRIBUTOR_ID = 48749 THEN 0  -- Staff discount
            ELSE t.AMT_NET_DISTRIBUTOR_FEE
        END,
        CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365, 48321, 54034) THEN 'USD' ELSE t.CD_SALES_CURRENCY END,
        t.T_PRODUCT_TYPE,
        ABS(t.NUM_PCS),
        TRY_CAST(t.CD_TRANSACTION_VERSION AS FLOAT),
        CASE WHEN bk.DT_CREATED > t.DT_TRANSACTION THEN bk.DT_CREATED ELSE t.DT_TRANSACTION END
    FROM [L0_PRIO_SALES_TRANSACTION] t
    INNER JOIN [L0_SRG_BOOKING] bk ON bk.CD_ORDER_ID = t.CD_ORDER_ID AND bk.CD_PRODUCT_ID = t.CD_PRODUCT_ID
    INNER JOIN [L0_SRG_AGENT]   a  ON a.CD_DISTRIBUTOR_ID = t.CD_DISTRIBUTOR_ID AND a.CD_SOURCE = 'PRIO'
    LEFT JOIN  [L0_SRG_SALES_TRANSACTION] ex
        ON ex.CD_TRANSACTION_ID = REPLACE(t.CD_TRANSACTION_ID, '-', '')
        AND ex.CD_INVOICE_TYPE = 'Discounts'
    WHERE
        t.FL_IS_PROCESSED = 0
        AND ex.ID_SALES_TRANSACTION IS NULL
        AND t.CD_PRODUCT_ID = 0;  -- Discount lines have no product

    /*
    ============================================================
    STEP 4: UPDATE existing transactions that have new versions
    ============================================================
    */
    UPDATE st
    SET
        st.[AMT_REVENUE]          = ABS(t.AMT_SALE_PRICE),
        st.[CD_ORDER_STATUS]      = t.CD_INVOICE_STATUS,
        st.[AMT_COMMISSION]       = CASE WHEN st.CD_INVOICE_CATEGORY = 4
                                         THEN CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404, 4365)
                                                   THEN ISNULL(t.AMT_NET_DISTRIBUTOR_FEE,0) + ISNULL(t.AMT_NET_RESELLER_FEE,0)
                                                   ELSE t.AMT_NET_DISTRIBUTOR_FEE END
                                         ELSE st.AMT_COMMISSION END,
        st.[AMT_SUPPLIER_PRICE]   = t.AMT_LOCAL_CURRENCY_PRICE,
        st.[VL_VERSION]           = TRY_CAST(t.CD_TRANSACTION_VERSION AS FLOAT),
        st.[CD_SALES_CURRENCY]    = CASE WHEN t.CD_DISTRIBUTOR_ID IN (49404,4365,48321,54034) THEN 'USD' ELSE t.CD_SALES_CURRENCY END,
        st.[CD_SUPPLIER_CURRENCY] = t.CD_SUPPLIER_CURRENCY,
        st.[DT_ORDER]             = CASE WHEN bk.DT_CREATED > t.DT_TRANSACTION THEN bk.DT_CREATED ELSE t.DT_TRANSACTION END,
        st.[DT_LAST_UPDATED]      = SYSDATETIME(),
        st.[FL_IS_PROCESSED_TO_GOLD] = 0  -- Reset so Gold picks up the update
    FROM [L0_PRIO_SALES_TRANSACTION] t
    INNER JOIN [L0_SRG_BOOKING]     bk ON bk.CD_ORDER_ID = t.CD_ORDER_ID AND bk.CD_PRODUCT_ID = t.CD_PRODUCT_ID
    INNER JOIN [L0_SRG_PRODUCT]     p  ON p.CD_PRODUCT_ID = t.CD_PRODUCT_ID AND p.CD_SOURCE = 'PRIO'
    INNER JOIN [L0_SRG_SALES_TRANSACTION] st
        ON st.CD_TRANSACTION_ID = REPLACE(t.CD_TRANSACTION_ID, '-', '')
        AND st.ID_PRODUCT = p.ID_PRODUCT
    WHERE t.FL_IS_PROCESSED = 0 AND t.CD_PRODUCT_ID > 0;

    /*
    ============================================================
    STEP 5: Net agent adjustment
    Revenue for net agents = Revenue - Commission (commission already included in price)
    ============================================================
    */
    UPDATE st
    SET
        st.[AMT_REVENUE]    = st.AMT_REVENUE - ABS(st.AMT_COMMISSION),
        st.[AMT_COMMISSION] = 0
    FROM [L0_SRG_SALES_TRANSACTION] st
    INNER JOIN [L0_SRG_BOOKING] bk ON bk.ID_BOOKING = st.ID_BOOKING
    INNER JOIN [L0_SRG_AGENT]   a  ON a.ID_AGENT = bk.ID_AGENT
    WHERE
        a.FL_IS_NET_AGENT = 1
        AND st.AMT_REVENUE <> 0
        AND st.CD_INVOICE_CATEGORY = 4
        AND bk.CD_ORDER_ID IN (
            SELECT DISTINCT CD_ORDER_ID FROM [L0_PRIO_SALES_TRANSACTION] WHERE FL_IS_PROCESSED = 0
        );

    /*
    ============================================================
    STEP 6: CostPlus agent adjustment
    Revenue = LocalCurrencyPrice × (1 + AgentMarkup)
    ============================================================
    */
    UPDATE st
    SET
        st.[AMT_REVENUE]          = bk_detail.AMT_LOCAL_CURRENCY_PRICE * (1 + a.VL_AGENT_MARKUP),
        st.[AMT_COMMISSION]       = 0,
        st.[CD_SALES_CURRENCY]    = st.CD_SUPPLIER_CURRENCY
    FROM [L0_SRG_SALES_TRANSACTION] st
    INNER JOIN [L0_SRG_BOOKING] bk ON bk.ID_BOOKING = st.ID_BOOKING
    INNER JOIN [L0_SRG_AGENT]   a  ON a.ID_AGENT = bk.ID_AGENT AND a.T_DISTRIBUTOR_TYPE = 'CostPlus'
    INNER JOIN (
        SELECT CD_ORDER_ID, CD_PRODUCT_ID, AMT_LOCAL_CURRENCY_PRICE
        FROM [L0_PRIO_SALES_TRANSACTION]
        WHERE FL_IS_PROCESSED = 0
    ) bk_detail ON bk_detail.CD_ORDER_ID = bk.CD_ORDER_ID AND bk_detail.CD_PRODUCT_ID = bk.CD_PRODUCT_ID
    WHERE
        st.AMT_REVENUE <> 0
        AND st.CD_INVOICE_CATEGORY = 4
        AND bk.CD_ORDER_ID IN (
            SELECT DISTINCT CD_ORDER_ID FROM [L0_PRIO_SALES_TRANSACTION] WHERE FL_IS_PROCESSED = 0
        );

    /*
    ============================================================
    STEP 7: Mark source rows as processed
    ============================================================
    */
    UPDATE [L0_PRIO_SALES_TRANSACTION]
        SET [FL_IS_PROCESSED] = 1,
            [DT_LAST_UPDATE]  = SYSDATETIME()
    WHERE [FL_IS_PROCESSED] = 0;

END;
