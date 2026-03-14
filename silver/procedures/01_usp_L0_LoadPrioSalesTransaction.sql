/*
================================================================================
 Procedure: usp_L0_LoadPrioSalesTransaction
 Layer: Silver (L0)
 Source: BRONZE.PRIO_CSV_SALES_TRANSACTION (Lakehouse via shortcut)
 Target: L0_PRIO_SALES_TRANSACTION
 Old equivalent: vimport_prio_transaction_staging logic (view on import_prio_transaction_staging_v2)
================================================================================
 Purpose:
   Loads new, unprocessed transaction rows from the Bronze Lakehouse Delta table
   into the Silver warehouse table L0_PRIO_SALES_TRANSACTION.
   Applies:
     - Deduplication: keep only the latest version of each transaction
       (RANK by last_modified_at DESC, Transaction_Version DESC)
     - Type casting: all Bronze columns arrive as strings → cast to INT/DECIMAL/DATE
     - Data cleansing: trim whitespace, normalise empty strings to NULL
     - Exclusion of soft-deletes (bIsReplaced=1, ManuallyDeleted=1)
     - Incremental pattern: only load rows newer than the last processed watermark
================================================================================
 Parameters:
   @dtWatermark  - Load rows with insert_date > this value. NULL = full reload.
================================================================================
 Author: AWG_DWH Migration
 Date: 2026-03-14
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L0_LoadPrioSalesTransaction]
    @dtWatermark DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Default watermark: last max DT_INSERT in target, or epoch
    IF @dtWatermark IS NULL
        SELECT @dtWatermark = ISNULL(MAX([DT_INSERT]), '1900-01-01')
        FROM [L0_PRIO_SALES_TRANSACTION];

    /*
    ============================================================
    STEP 1: Deduplicate bronze rows - keep latest per Transaction_ID
    ============================================================
    Mirrors old logic: rank() over(PARTITION BY transaction_id
    ORDER BY last_modified_at DESC, isnull(transaction_version,'1') desc)
    Excludes: bIsReplaced=1, ManuallyDeleted=1
    ============================================================
    */
    WITH DeduplicatedBronze AS (
        SELECT
            *,
            RANK() OVER (
                PARTITION BY [Transaction_ID]
                ORDER BY
                    TRY_CAST([last_modified_at] AS DATETIME2) DESC,
                    TRY_CAST(ISNULL([Transaction_Version], '1') AS FLOAT) DESC
            ) AS rn
        FROM [BRONZE].[PRIO_CSV_SALES_TRANSACTION]  -- Cross-database reference to Lakehouse shortcut
        WHERE
            ISNULL(CAST([bIsReplaced] AS BIT), 0) = 0
            AND ISNULL(CAST([ManuallyDeleted] AS BIT), 0) = 0
            AND TRY_CAST([insert_date] AS DATETIME2) > @dtWatermark
    ),
    LatestOnly AS (
        SELECT * FROM DeduplicatedBronze WHERE rn = 1
    )

    /*
    ============================================================
    STEP 2: Merge into Silver - insert new, skip existing
    ============================================================
    Note: Updates to existing transactions are handled by the Silver
    merge procedures (usp_L0_MergeBookings, usp_L0_MergeSalesTransactions).
    Here we only INSERT new transaction IDs not yet in Silver.
    ============================================================
    */
    MERGE [L0_PRIO_SALES_TRANSACTION] AS tgt
    USING (
        SELECT
            -- Transaction identifiers
            TRIM([Transaction_ID])                                         AS CD_TRANSACTION_ID,
            TRIM([Order_ID])                                               AS CD_ORDER_ID,
            TRIM([Transaction_Version])                                    AS CD_TRANSACTION_VERSION,
            TRIM([Pass_No.])                                               AS CD_PASS_NO,
            TRIM([Client_Reference_No.])                                   AS CD_CLIENT_REFERENCE_NO,
            TRIM([PSP_Reference])                                          AS CD_PSP_REFERENCE,
            TRIM([Ticket_Type_ID])                                         AS CD_TICKET_TYPE_ID,
            TRIM([Channel_ID])                                             AS CD_CHANNEL_ID,

            -- Dates
            TRY_CAST(
                CASE WHEN LEN(TRIM([Date])) > 0 AND LEN(TRIM([Time])) > 0
                     THEN TRIM([Date]) + ' ' + TRIM([Time])
                     ELSE NULL END
            AS DATETIME2(0))                                               AS DT_TRANSACTION,

            TRY_CAST(
                CASE WHEN LEN(TRIM([Creation_Date])) > 0 AND LEN(TRIM([Creation_Time])) > 0
                     THEN TRIM([Creation_Date]) + ' ' + TRIM([Creation_Time])
                     ELSE NULL END
            AS DATETIME2(0))                                               AS DT_CREATED,

            TRY_CAST(NULLIF(TRIM([Reservation_Date]), '') AS DATE)         AS DT_RESERVATION,
            TRY_CAST(NULLIF(TRIM([Verification_Date]), '') AS DATE)        AS DT_VERIFICATION,
            TRY_CAST(NULLIF(TRIM([last_modified_at]), '') AS DATETIME2(0)) AS DT_LAST_MODIFIED,

            -- Reseller
            NULLIF(TRIM([Reseller_ID]), '')                                AS CD_RESELLER_ID,
            NULLIF(TRIM([Reseller_Name]), '')                              AS T_RESELLER_NAME,

            -- Supplier
            TRY_CAST(NULLIF(TRIM([Supplier_ID]), '') AS INT)               AS CD_SUPPLIER_ID,
            NULLIF(TRIM([Supplier_Name]), '')                              AS T_SUPPLIER_NAME,

            -- Distributor / Agent
            TRY_CAST(NULLIF(TRIM([Distributor_ID]), '') AS INT)            AS CD_DISTRIBUTOR_ID,
            NULLIF(TRIM([Distributor_Name]), '')                           AS T_DISTRIBUTOR_NAME,
            NULLIF(TRIM([parent_account_id]), '')                          AS CD_PARENT_ACCOUNT_ID,
            NULLIF(TRIM([Parent_account_name]), '')                        AS T_PARENT_ACCOUNT_NAME,
            NULLIF(TRIM([client_type]), '')                                AS T_CLIENT_TYPE,
            NULLIF(TRIM([vat_no]), '')                                     AS T_VAT_NO,

            -- Channel
            NULLIF(TRIM([Channel_Type]), '')                               AS CD_CHANNEL_TYPE,
            NULLIF(TRIM([Channel_Name]), '')                               AS T_CHANNEL_NAME,
            NULLIF(TRIM([Saledesk_Name]), '')                              AS T_SALEDESK_NAME,

            -- Product
            TRY_CAST(NULLIF(TRIM([Product_ID]), '') AS INT)                AS CD_PRODUCT_ID,
            NULLIF(TRIM([Product_Type_Title]), '')                         AS T_PRODUCT_TYPE_TITLE,
            NULLIF(TRIM([Product_Type]), '')                               AS T_PRODUCT_TYPE,
            NULLIF(TRIM([Combi_Type]), '')                                 AS T_COMBI_TYPE,
            NULLIF(TRIM([Statement_Type]), '')                             AS T_STATEMENT_TYPE,

            -- Quantities
            TRY_CAST(NULLIF(TRIM([Pcs]), '') AS INT)                       AS NUM_PCS,
            TRY_CAST(NULLIF(TRIM([Pax]), '') AS INT)                       AS NUM_PAX,

            -- Currencies
            NULLIF(TRIM([Sales_Currency]), '')                             AS CD_SALES_CURRENCY,
            NULLIF(TRIM([Currency]), '')                                   AS CD_SUPPLIER_CURRENCY,

            -- Sales amounts
            TRY_CAST(NULLIF(TRIM([List_Price]), '') AS DECIMAL(19,4))      AS AMT_LIST_PRICE,
            TRY_CAST(NULLIF(TRIM([Sale_Price]), '') AS DECIMAL(19,4))      AS AMT_SALE_PRICE,
            TRY_CAST(NULLIF(TRIM([Net_Sale_Price]), '') AS DECIMAL(19,4))  AS AMT_NET_SALE_PRICE,
            TRY_CAST(NULLIF(TRIM([Distributor_Discount]),'') AS DECIMAL(19,4)) AS AMT_DISTRIBUTOR_DISCOUNT,
            TRY_CAST(NULLIF(TRIM([General_Tax]), '') AS DECIMAL(19,4))     AS AMT_GENERAL_TAX,

            -- Supplier amounts
            TRY_CAST(NULLIF(TRIM([Supplier_Price]), '') AS DECIMAL(19,4))     AS AMT_SUPPLIER_PRICE,
            TRY_CAST(NULLIF(TRIM([Net_Supplier_Price]),'') AS DECIMAL(19,4))  AS AMT_NET_SUPPLIER_PRICE,
            TRY_CAST(NULLIF(TRIM([Supplier_Tax]), '') AS DECIMAL(19,4))       AS AMT_SUPPLIER_TAX,
            TRY_CAST(NULLIF(TRIM([Local_Currency_Price]),'') AS DECIMAL(19,4)) AS AMT_LOCAL_CURRENCY_PRICE,
            TRY_CAST(NULLIF(TRIM([Local_Currency_Net_Price]),'') AS DECIMAL(19,4)) AS AMT_LOCAL_CURRENCY_NET_PRICE,

            -- Fees
            NULLIF(TRIM([Market_Merchant_Name]), '')                           AS T_MERCHANT_NAME,
            TRY_CAST(NULLIF(TRIM([Market_Merchant_Fee]),'') AS DECIMAL(19,4)) AS AMT_MERCHANT_FEE,
            TRY_CAST(NULLIF(TRIM([Net_Market_Merchant_Fee]),'') AS DECIMAL(19,4)) AS AMT_NET_MERCHANT_FEE,
            TRY_CAST(NULLIF(TRIM([Market_Merchant_Tax]),'') AS DECIMAL(19,4)) AS AMT_MERCHANT_TAX,
            TRY_CAST(NULLIF(TRIM([Reseller_Fee]), '') AS DECIMAL(19,4))       AS AMT_RESELLER_FEE,
            TRY_CAST(NULLIF(TRIM([Net_Reseller_Fee]),'') AS DECIMAL(19,4))    AS AMT_NET_RESELLER_FEE,
            TRY_CAST(NULLIF(TRIM([Reseller_Tax]), '') AS DECIMAL(19,4))       AS AMT_RESELLER_TAX,
            TRY_CAST(NULLIF(TRIM([Distributor_Fee]),'') AS DECIMAL(19,4))     AS AMT_DISTRIBUTOR_FEE,
            TRY_CAST(NULLIF(TRIM([Net_Distributor_Fee]),'') AS DECIMAL(19,4)) AS AMT_NET_DISTRIBUTOR_FEE,
            TRY_CAST(NULLIF(TRIM([Distributor_Tax]),'') AS DECIMAL(19,4))     AS AMT_DISTRIBUTOR_TAX,
            TRY_CAST(NULLIF(TRIM([Affiliate_Fee]),'') AS DECIMAL(19,4))       AS AMT_AFFILIATE_FEE,
            TRY_CAST(NULLIF(TRIM([Net_Affiliate_Fee]),'') AS DECIMAL(19,4))   AS AMT_NET_AFFILIATE_FEE,
            TRY_CAST(NULLIF(TRIM([Affiliate_Tax]),'') AS DECIMAL(19,4))       AS AMT_AFFILIATE_TAX,

            -- Status / metadata
            NULLIF(TRIM([Invoice_Status]), '')                             AS CD_INVOICE_STATUS,
            NULLIF(TRIM([Retail_Payment_Method]), '')                      AS T_PAYMENT_METHOD,
            NULLIF(TRIM([Guest_Name]), '')                                 AS T_GUEST_NAME,
            NULLIF(TRIM([Flag_Name]), '')                                  AS T_FLAG_NAME,
            NULLIF(TRIM([Flag_Value]), '')                                 AS T_FLAG_VALUE,
            NULLIF(TRIM([File_name]), '')                                  AS T_FILE_NAME,
            NULLIF(TRIM([wdw_payment_options]), '')                        AS T_WDW_PAYMENT_OPTIONS
        FROM LatestOnly
    ) AS src
    ON tgt.[CD_TRANSACTION_ID] = src.CD_TRANSACTION_ID

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            [CD_TRANSACTION_ID], [CD_ORDER_ID], [CD_TRANSACTION_VERSION], [CD_PASS_NO],
            [CD_CLIENT_REFERENCE_NO], [CD_PSP_REFERENCE], [CD_TICKET_TYPE_ID], [CD_CHANNEL_ID],
            [DT_TRANSACTION], [DT_CREATED], [DT_RESERVATION], [DT_VERIFICATION], [DT_LAST_MODIFIED],
            [CD_RESELLER_ID], [T_RESELLER_NAME],
            [CD_SUPPLIER_ID], [T_SUPPLIER_NAME],
            [CD_DISTRIBUTOR_ID], [T_DISTRIBUTOR_NAME], [CD_PARENT_ACCOUNT_ID], [T_PARENT_ACCOUNT_NAME],
            [T_CLIENT_TYPE], [T_VAT_NO],
            [CD_CHANNEL_TYPE], [T_CHANNEL_NAME], [T_SALEDESK_NAME],
            [CD_PRODUCT_ID], [T_PRODUCT_TYPE_TITLE], [T_PRODUCT_TYPE], [T_COMBI_TYPE], [T_STATEMENT_TYPE],
            [NUM_PCS], [NUM_PAX],
            [CD_SALES_CURRENCY], [CD_SUPPLIER_CURRENCY],
            [AMT_LIST_PRICE], [AMT_SALE_PRICE], [AMT_NET_SALE_PRICE], [AMT_DISTRIBUTOR_DISCOUNT], [AMT_GENERAL_TAX],
            [AMT_SUPPLIER_PRICE], [AMT_NET_SUPPLIER_PRICE], [AMT_SUPPLIER_TAX],
            [AMT_LOCAL_CURRENCY_PRICE], [AMT_LOCAL_CURRENCY_NET_PRICE],
            [T_MERCHANT_NAME], [AMT_MERCHANT_FEE], [AMT_NET_MERCHANT_FEE], [AMT_MERCHANT_TAX],
            [AMT_RESELLER_FEE], [AMT_NET_RESELLER_FEE], [AMT_RESELLER_TAX],
            [AMT_DISTRIBUTOR_FEE], [AMT_NET_DISTRIBUTOR_FEE], [AMT_DISTRIBUTOR_TAX],
            [AMT_AFFILIATE_FEE], [AMT_NET_AFFILIATE_FEE], [AMT_AFFILIATE_TAX],
            [CD_INVOICE_STATUS], [T_PAYMENT_METHOD], [T_GUEST_NAME],
            [T_FLAG_NAME], [T_FLAG_VALUE], [T_FILE_NAME], [T_WDW_PAYMENT_OPTIONS]
        )
        VALUES (
            src.CD_TRANSACTION_ID, src.CD_ORDER_ID, src.CD_TRANSACTION_VERSION, src.CD_PASS_NO,
            src.CD_CLIENT_REFERENCE_NO, src.CD_PSP_REFERENCE, src.CD_TICKET_TYPE_ID, src.CD_CHANNEL_ID,
            src.DT_TRANSACTION, src.DT_CREATED, src.DT_RESERVATION, src.DT_VERIFICATION, src.DT_LAST_MODIFIED,
            src.CD_RESELLER_ID, src.T_RESELLER_NAME,
            src.CD_SUPPLIER_ID, src.T_SUPPLIER_NAME,
            src.CD_DISTRIBUTOR_ID, src.T_DISTRIBUTOR_NAME, src.CD_PARENT_ACCOUNT_ID, src.T_PARENT_ACCOUNT_NAME,
            src.T_CLIENT_TYPE, src.T_VAT_NO,
            src.CD_CHANNEL_TYPE, src.T_CHANNEL_NAME, src.T_SALEDESK_NAME,
            src.CD_PRODUCT_ID, src.T_PRODUCT_TYPE_TITLE, src.T_PRODUCT_TYPE, src.T_COMBI_TYPE, src.T_STATEMENT_TYPE,
            src.NUM_PCS, src.NUM_PAX,
            src.CD_SALES_CURRENCY, src.CD_SUPPLIER_CURRENCY,
            src.AMT_LIST_PRICE, src.AMT_SALE_PRICE, src.AMT_NET_SALE_PRICE, src.AMT_DISTRIBUTOR_DISCOUNT, src.AMT_GENERAL_TAX,
            src.AMT_SUPPLIER_PRICE, src.AMT_NET_SUPPLIER_PRICE, src.AMT_SUPPLIER_TAX,
            src.AMT_LOCAL_CURRENCY_PRICE, src.AMT_LOCAL_CURRENCY_NET_PRICE,
            src.T_MERCHANT_NAME, src.AMT_MERCHANT_FEE, src.AMT_NET_MERCHANT_FEE, src.AMT_MERCHANT_TAX,
            src.AMT_RESELLER_FEE, src.AMT_NET_RESELLER_FEE, src.AMT_RESELLER_TAX,
            src.AMT_DISTRIBUTOR_FEE, src.AMT_NET_DISTRIBUTOR_FEE, src.AMT_DISTRIBUTOR_TAX,
            src.AMT_AFFILIATE_FEE, src.AMT_NET_AFFILIATE_FEE, src.AMT_AFFILIATE_TAX,
            src.CD_INVOICE_STATUS, src.T_PAYMENT_METHOD, src.T_GUEST_NAME,
            src.T_FLAG_NAME, src.T_FLAG_VALUE, src.T_FILE_NAME, src.T_WDW_PAYMENT_OPTIONS
        )

    WHEN MATCHED AND (
        -- Update if version or modification date has changed
        tgt.[CD_TRANSACTION_VERSION] <> src.CD_TRANSACTION_VERSION
        OR tgt.[DT_LAST_MODIFIED] < src.DT_LAST_MODIFIED
    ) THEN
        UPDATE SET
            [CD_TRANSACTION_VERSION]   = src.CD_TRANSACTION_VERSION,
            [DT_LAST_MODIFIED]         = src.DT_LAST_MODIFIED,
            [AMT_SALE_PRICE]           = src.AMT_SALE_PRICE,
            [AMT_NET_SALE_PRICE]       = src.AMT_NET_SALE_PRICE,
            [AMT_NET_DISTRIBUTOR_FEE]  = src.AMT_NET_DISTRIBUTOR_FEE,
            [AMT_LOCAL_CURRENCY_PRICE] = src.AMT_LOCAL_CURRENCY_PRICE,
            [AMT_NET_SUPPLIER_PRICE]   = src.AMT_NET_SUPPLIER_PRICE,
            [CD_SUPPLIER_CURRENCY]     = src.CD_SUPPLIER_CURRENCY,
            [CD_SALES_CURRENCY]        = src.CD_SALES_CURRENCY,
            [CD_INVOICE_STATUS]        = src.CD_INVOICE_STATUS,
            [DT_TRANSACTION]           = src.DT_TRANSACTION,
            [T_FLAG_NAME]              = src.T_FLAG_NAME,
            [T_FLAG_VALUE]             = src.T_FLAG_VALUE,
            [FL_IS_PROCESSED]          = 0,  -- Reset processing flag so downstream picks up the update
            [DT_LAST_UPDATE]           = SYSDATETIME();

END;
