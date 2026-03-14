/*
================================================================================
 Procedure: usp_L0_MergeProducts
 Layer: Silver (L0)
 Source: L0_PRIO_SALES_TRANSACTION (unprocessed), L0_SRG_SUPPLIER
 Target: L0_SRG_PRODUCT
 Old equivalent: usp_ProcessGeneralDimensions (Products section)
================================================================================
 Purpose:
   MERGE new and updated product records into the L0_SRG_PRODUCT surrogation table.
   - Uses longest product name observed across all transactions (MAX strategy)
   - Joins to L0_SRG_SUPPLIER to get the supplier surrogate key
   - Excludes Product_ID = 0 (discount lines), Supplier_ID = 0 (unlinked)
   - Excludes known non-product titles ('Reprice Discount', 'Reprice Surcharge')
   - Excludes product 23321 (known data quality issue from old system)
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L0_MergeProducts]
AS
BEGIN
    SET NOCOUNT ON;

    WITH NewProducts AS (
        SELECT
            t.CD_PRODUCT_ID,
            t.CD_SUPPLIER_ID,
            s.ID_SUPPLIER,
            MAX(t.T_PRODUCT_TYPE_TITLE) AS T_PRODUCT_NAME  -- Use longest name observed
        FROM [L0_PRIO_SALES_TRANSACTION] t
        INNER JOIN [L0_SRG_SUPPLIER] s
            ON s.CD_SUPPLIER_ID = t.CD_SUPPLIER_ID
            AND s.CD_SOURCE = 'PRIO'
        WHERE
            t.FL_IS_PROCESSED = 0
            AND t.CD_PRODUCT_ID > 0
            AND t.CD_SUPPLIER_ID > 0
            AND t.CD_PRODUCT_ID <> 23321                          -- Known bad product ID
            AND LEN(ISNULL(t.T_PRODUCT_TYPE_TITLE, '')) > 3
            AND t.T_PRODUCT_TYPE_TITLE NOT IN ('Reprice Discount', 'Reprice Surcharge')
        GROUP BY
            t.CD_PRODUCT_ID,
            t.CD_SUPPLIER_ID,
            s.ID_SUPPLIER
    )
    MERGE [L0_SRG_PRODUCT] AS tgt
    USING NewProducts AS src
        ON tgt.[CD_PRODUCT_ID] = src.CD_PRODUCT_ID
        AND tgt.[CD_SUPPLIER_ID] = src.CD_SUPPLIER_ID
        AND tgt.[CD_SOURCE] = 'PRIO'

    WHEN MATCHED AND tgt.[T_PRODUCT_NAME] <> src.T_PRODUCT_NAME THEN
        UPDATE SET
            [T_PRODUCT_NAME]   = src.T_PRODUCT_NAME,
            [ID_SUPPLIER]      = src.ID_SUPPLIER,
            [DT_LAST_UPDATED]  = SYSDATETIME()

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            [ID_PRODUCT],
            [CD_PRODUCT_ID],
            [CD_SUPPLIER_ID],
            [CD_SOURCE],
            [ID_SUPPLIER],
            [T_PRODUCT_NAME],
            [FL_USE_PRIO_NAME],
            [DT_CREATED],
            [DT_LAST_UPDATED]
        )
        VALUES (
            ISNULL((SELECT MAX(ID_PRODUCT) FROM L0_SRG_PRODUCT), 0) + 1,
            src.CD_PRODUCT_ID,
            src.CD_SUPPLIER_ID,
            'PRIO',
            src.ID_SUPPLIER,
            src.T_PRODUCT_NAME,
            1,
            SYSDATETIME(),
            SYSDATETIME()
        );

    -- Fix: re-apply longest name (mirrors old "fix product names with longest name" step)
    UPDATE p
        SET p.[T_PRODUCT_NAME] = src.MaxName
    FROM [L0_SRG_PRODUCT] p
    INNER JOIN (
        SELECT
            CD_PRODUCT_ID,
            MAX(T_PRODUCT_TYPE_TITLE) AS MaxName
        FROM [L0_PRIO_SALES_TRANSACTION]
        WHERE
            CD_PRODUCT_ID > 0
            AND CD_SUPPLIER_ID > 0
            AND T_PRODUCT_TYPE_TITLE NOT IN ('Reprice Discount', 'Reprice Surcharge')
        GROUP BY CD_PRODUCT_ID
        HAVING MAX(T_PRODUCT_TYPE_TITLE) <> ''
    ) AS src ON src.CD_PRODUCT_ID = p.CD_PRODUCT_ID
    WHERE p.[T_PRODUCT_NAME] <> src.MaxName;

    -- Mark package products: FL_IS_PACKAGE = 1 if their supplier is a package supplier
    UPDATE p
        SET p.[FL_IS_PACKAGE] = 1
    FROM [L0_SRG_PRODUCT] p
    INNER JOIN [L0_SRG_SUPPLIER] s ON s.[ID_SUPPLIER] = p.[ID_SUPPLIER]
    WHERE s.[FL_IS_PACKAGE_SUPPLIER] = 1;

END;
