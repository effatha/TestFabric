/*
================================================================================
 Procedure: usp_L1_OrchestratePrioLoad
 Layer: Gold (L1) - Orchestration
 Old equivalent: usp_ProcessPrioBookings (main orchestrator)
================================================================================
 Purpose:
   Master orchestration procedure for the Prio transaction ETL pipeline.
   Executes each step in order, with error handling and logging.
   This is the single entry point called by the Fabric Data Pipeline.

 Execution order:
   1. usp_L0_LoadPrioSalesTransaction  → Bronze → Silver (cleansed staging)
   2. usp_L0_MergeSuppliers            → Upsert supplier surrogation
   3. usp_L0_MergeProducts             → Upsert product surrogation
   4. usp_L0_MergeAgents               → Upsert agent surrogation
   5. usp_L0_MergeBookings             → Upsert booking surrogation + enrichment
   6. usp_L0_MergeSalesTransactions    → Upsert Silver transaction lines
   7. usp_L1_LoadDimensions            → Sync Silver → Gold dimensions
   8. usp_L1_LoadFactSalesTransaction  → Load Gold fact + exchange rates

 Parameters:
   @bReload  BIT = 0  -- Set to 1 to delete and reload all data for unprocessed transactions
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L1_OrchestratePrioLoad]
    @bReload BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tMsg        NVARCHAR(MAX);
    DECLARE @dtStart     DATETIME2 = SYSDATETIME();
    DECLARE @dtStepStart DATETIME2;
    DECLARE @nRet        INT = 0;

    /*
    ============================================================
    STEP 1: Bronze → Silver: Load and cleanse Prio transaction CSV
    ============================================================
    */
    SET @dtStepStart = SYSDATETIME();
    BEGIN TRY
        EXEC [dbo].[usp_L0_LoadPrioSalesTransaction];
    END TRY
    BEGIN CATCH
        SET @nRet = -1;
        SET @tMsg = 'ERROR usp_L0_LoadPrioSalesTransaction: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    /*
    ============================================================
    STEP 2: Upsert Suppliers
    ============================================================
    */
    BEGIN TRY
        EXEC [dbo].[usp_L0_MergeSuppliers];
    END TRY
    BEGIN CATCH
        SET @nRet = -2;
        SET @tMsg = 'ERROR usp_L0_MergeSuppliers: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    /*
    ============================================================
    STEP 3: Upsert Products
    ============================================================
    */
    BEGIN TRY
        EXEC [dbo].[usp_L0_MergeProducts];
    END TRY
    BEGIN CATCH
        SET @nRet = -3;
        SET @tMsg = 'ERROR usp_L0_MergeProducts: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    /*
    ============================================================
    STEP 4: Upsert Agents
    ============================================================
    */
    BEGIN TRY
        EXEC [dbo].[usp_L0_MergeAgents];
    END TRY
    BEGIN CATCH
        SET @nRet = -4;
        SET @tMsg = 'ERROR usp_L0_MergeAgents: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    /*
    ============================================================
    STEP 5: Upsert Bookings
    ============================================================
    */
    BEGIN TRY
        EXEC [dbo].[usp_L0_MergeBookings];
    END TRY
    BEGIN CATCH
        SET @nRet = -5;
        SET @tMsg = 'ERROR usp_L0_MergeBookings: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    /*
    ============================================================
    STEP 6: Upsert Silver Sales Transactions
    ============================================================
    */
    BEGIN TRY
        EXEC [dbo].[usp_L0_MergeSalesTransactions];
    END TRY
    BEGIN CATCH
        SET @nRet = -6;
        SET @tMsg = 'ERROR usp_L0_MergeSalesTransactions: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    /*
    ============================================================
    STEP 7: Sync Silver → Gold Dimensions
    ============================================================
    */
    BEGIN TRY
        EXEC [dbo].[usp_L1_LoadDimensions];
    END TRY
    BEGIN CATCH
        SET @nRet = -7;
        SET @tMsg = 'ERROR usp_L1_LoadDimensions: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    /*
    ============================================================
    STEP 8: Load Gold Fact + Exchange Rates
    ============================================================
    */
    BEGIN TRY
        EXEC [dbo].[usp_L1_LoadFactSalesTransaction];
    END TRY
    BEGIN CATCH
        SET @nRet = -8;
        SET @tMsg = 'ERROR usp_L1_LoadFactSalesTransaction: ' + ERROR_MESSAGE();
        GOTO ExitWithError;
    END CATCH;

    SET @nRet = 0;
    RETURN @nRet;

ExitWithError:
    PRINT @tMsg;
    RETURN @nRet;

END;
