/*
================================================================================
 Procedure: usp_L0_MergeSuppliers
 Layer: Silver (L0)
 Source: L0_PRIO_SALES_TRANSACTION (unprocessed rows)
 Target: L0_SRG_SUPPLIER
 Old equivalent: usp_ProcessGeneralDimensions (Suppliers section)
================================================================================
 Purpose:
   MERGE new and updated supplier records from unprocessed Silver transaction
   rows into the L0_SRG_SUPPLIER surrogation table.
   - NEW supplier: INSERT with next surrogate key
   - EXISTING supplier with changed name: UPDATE T_SUPPLIER_NAME (SCD Type 1)
   Excludes transactions where Supplier_ID = 0 (discounts/virtual lines).
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L0_MergeSuppliers]
AS
BEGIN
    SET NOCOUNT ON;

    WITH NewSuppliers AS (
        SELECT
            CD_SUPPLIER_ID,
            MIN(T_SUPPLIER_NAME) AS T_SUPPLIER_NAME
        FROM [L0_PRIO_SALES_TRANSACTION]
        WHERE
            FL_IS_PROCESSED = 0
            AND CD_SUPPLIER_ID > 0
            AND CD_TRANSACTION_VERSION <> ''
        GROUP BY CD_SUPPLIER_ID
    )
    MERGE [L0_SRG_SUPPLIER] AS tgt
    USING NewSuppliers AS src
        ON tgt.[CD_SUPPLIER_ID] = src.CD_SUPPLIER_ID
        AND tgt.[CD_SOURCE] = 'PRIO'

    WHEN MATCHED AND tgt.[T_SUPPLIER_NAME] <> src.T_SUPPLIER_NAME THEN
        UPDATE SET
            [T_SUPPLIER_NAME]  = src.T_SUPPLIER_NAME,
            [DT_LAST_UPDATED]  = SYSDATETIME()

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            [ID_SUPPLIER],
            [CD_SUPPLIER_ID],
            [CD_SOURCE],
            [T_SUPPLIER_NAME],
            [FL_USE_PRIO_NAME],
            [DT_CREATED],
            [DT_LAST_UPDATED]
        )
        VALUES (
            -- Surrogate key: next available (Fabric Warehouse uses SEQUENCE or MAX+1)
            ISNULL((SELECT MAX(ID_SUPPLIER) FROM L0_SRG_SUPPLIER), 0) + 1,
            src.CD_SUPPLIER_ID,
            'PRIO',
            src.T_SUPPLIER_NAME,
            1,
            SYSDATETIME(),
            SYSDATETIME()
        );

    -- Mark package suppliers based on supplier-level flag set via SharePoint (MD_LIST_AGENTS enrichment)
    -- Note: FL_IS_PACKAGE_SUPPLIER is maintained manually via MD_LIST_PRODUCTS SharePoint sync
END;
