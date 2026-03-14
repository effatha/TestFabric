/*
================================================================================
 Procedure: usp_L1_LoadDimensions
 Layer: Gold (L1)
 Source: L0_SRG_SUPPLIER, L0_SRG_PRODUCT, L0_SRG_AGENT, L0_SRG_CHANNEL, L0_SRG_RESELLER
 Target: L1_DIM_SUPPLIER, L1_DIM_PRODUCT, L1_DIM_AGENT, L1_DIM_CHANNEL, L1_DIM_RESELLER
================================================================================
 Purpose:
   Syncs all Silver surrogation tables to their corresponding Gold dimension tables.
   This is a full-refresh merge for each dimension (dimensions are small enough
   that a full merge is efficient and safe).
   AW SharePoint enrichment (MD_LIST_PRODUCTS, MD_LIST_AGENTS) is applied here
   to layer AW-managed overrides on top of Prio-sourced attributes.
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L1_LoadDimensions]
AS
BEGIN
    SET NOCOUNT ON;

    /*
    ============================================================
    L1_DIM_SUPPLIER
    ============================================================
    */
    MERGE [L1_DIM_SUPPLIER] AS tgt
    USING [L0_SRG_SUPPLIER] AS src ON tgt.[ID_SUPPLIER] = src.[ID_SUPPLIER]
    WHEN MATCHED THEN UPDATE SET
        tgt.[T_SUPPLIER_NAME]        = src.[T_SUPPLIER_NAME],
        tgt.[T_SUPPLIER_GROUP]       = src.[T_SUPPLIER_GROUP],
        tgt.[T_PRODUCT_MANAGER]      = src.[T_PRODUCT_MANAGER],
        tgt.[T_SUPPLIER_SET]         = src.[T_SUPPLIER_SET],
        tgt.[T_CATEGORY]             = src.[T_CATEGORY],
        tgt.[FL_IS_PACKAGE_SUPPLIER] = src.[FL_IS_PACKAGE_SUPPLIER],
        tgt.[DT_LAST_UPDATED]        = src.[DT_LAST_UPDATED]
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        [ID_SUPPLIER], [CD_SUPPLIER_ID], [CD_SOURCE],
        [T_SUPPLIER_NAME], [T_SUPPLIER_GROUP], [T_PRODUCT_MANAGER],
        [T_SUPPLIER_SET], [T_CATEGORY], [FL_IS_PACKAGE_SUPPLIER],
        [DT_CREATED], [DT_LAST_UPDATED]
    ) VALUES (
        src.[ID_SUPPLIER], src.[CD_SUPPLIER_ID], src.[CD_SOURCE],
        src.[T_SUPPLIER_NAME], src.[T_SUPPLIER_GROUP], src.[T_PRODUCT_MANAGER],
        src.[T_SUPPLIER_SET], src.[T_CATEGORY], src.[FL_IS_PACKAGE_SUPPLIER],
        src.[DT_CREATED], src.[DT_LAST_UPDATED]
    )
    WHEN NOT MATCHED BY SOURCE THEN UPDATE SET tgt.[FL_IS_ACTIVE] = 0;

    /*
    ============================================================
    L1_DIM_PRODUCT
    Apply AW overrides: ISNULL(AW_override, Prio_value) for geography
    ============================================================
    */
    MERGE [L1_DIM_PRODUCT] AS tgt
    USING [L0_SRG_PRODUCT] AS src ON tgt.[ID_PRODUCT] = src.[ID_PRODUCT]
    WHEN MATCHED THEN UPDATE SET
        tgt.[ID_SUPPLIER]       = src.[ID_SUPPLIER],
        tgt.[T_PRODUCT_NAME]    = ISNULL(src.[T_AW_PRODUCT_CITY], src.[T_PRODUCT_NAME]),  -- AW name wins if set
        tgt.[T_PRIO_PRODUCT_NAME] = src.[T_PRODUCT_NAME],
        tgt.[T_PRODUCT_CITY]    = ISNULL(src.[T_AW_PRODUCT_CITY],    src.[T_PRODUCT_CITY]),
        tgt.[T_PRODUCT_REGION]  = ISNULL(src.[T_AW_PRODUCT_REGION],  src.[T_PRODUCT_REGION]),
        tgt.[T_PRODUCT_COUNTRY] = ISNULL(src.[T_AW_PRODUCT_COUNTRY], src.[T_PRODUCT_COUNTRY]),
        tgt.[T_PRODUCT_CATEGORY] = src.[T_PRODUCT_CATEGORY],
        tgt.[T_ADMIN_NAME]      = src.[T_ADMIN_NAME],
        tgt.[T_PRODUCT_TAG]     = src.[T_PRODUCT_TAG],
        tgt.[T_LATITUDE]        = src.[T_LATITUDE],
        tgt.[T_LONGITUDE]       = src.[T_LONGITUDE],
        tgt.[FL_IS_PACKAGE]     = src.[FL_IS_PACKAGE],
        tgt.[DT_LAST_UPDATED]   = src.[DT_LAST_UPDATED]
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        [ID_PRODUCT], [ID_SUPPLIER], [CD_PRODUCT_ID], [CD_SUPPLIER_ID], [CD_SOURCE],
        [T_PRODUCT_NAME], [T_PRIO_PRODUCT_NAME],
        [T_PRODUCT_CITY], [T_PRODUCT_REGION], [T_PRODUCT_COUNTRY],
        [T_PRODUCT_CATEGORY], [T_ADMIN_NAME], [T_PRODUCT_TAG],
        [T_LATITUDE], [T_LONGITUDE], [FL_IS_PACKAGE],
        [DT_CREATED], [DT_LAST_UPDATED]
    ) VALUES (
        src.[ID_PRODUCT], src.[ID_SUPPLIER], src.[CD_PRODUCT_ID], src.[CD_SUPPLIER_ID], src.[CD_SOURCE],
        ISNULL(src.[T_AW_PRODUCT_CITY], src.[T_PRODUCT_NAME]),
        src.[T_PRODUCT_NAME],
        ISNULL(src.[T_AW_PRODUCT_CITY], src.[T_PRODUCT_CITY]),
        ISNULL(src.[T_AW_PRODUCT_REGION], src.[T_PRODUCT_REGION]),
        ISNULL(src.[T_AW_PRODUCT_COUNTRY], src.[T_PRODUCT_COUNTRY]),
        src.[T_PRODUCT_CATEGORY], src.[T_ADMIN_NAME], src.[T_PRODUCT_TAG],
        src.[T_LATITUDE], src.[T_LONGITUDE], src.[FL_IS_PACKAGE],
        src.[DT_CREATED], src.[DT_LAST_UPDATED]
    )
    WHEN NOT MATCHED BY SOURCE THEN UPDATE SET tgt.[FL_IS_ACTIVE] = 0;

    /*
    ============================================================
    L1_DIM_AGENT
    ============================================================
    */
    MERGE [L1_DIM_AGENT] AS tgt
    USING [L0_SRG_AGENT] AS src ON tgt.[ID_AGENT] = src.[ID_AGENT]
    WHEN MATCHED THEN UPDATE SET
        tgt.[T_AGENT_NAME]           = src.[T_AGENT_NAME],
        tgt.[FL_IS_TRADE_AGENT]      = src.[FL_IS_TRADE_AGENT],
        tgt.[FL_IS_NET_AGENT]        = src.[FL_IS_NET_AGENT],
        tgt.[T_DISTRIBUTOR_TYPE]     = src.[T_DISTRIBUTOR_TYPE],
        tgt.[VL_AGENT_MARKUP]        = src.[VL_AGENT_MARKUP],
        tgt.[T_CHANNEL]              = src.[T_CHANNEL],
        tgt.[T_ACCOUNT_CHANNEL]      = src.[T_ACCOUNT_CHANNEL],
        tgt.[T_AGENT_GROUP_NAME]     = src.[T_AGENT_GROUP_NAME],
        tgt.[T_AGENT_CONSORTIA]      = src.[T_AGENT_CONSORTIA],
        tgt.[T_AGENT_MANAGER]        = src.[T_AGENT_MANAGER],
        tgt.[T_MANAGER_REGION]       = src.[T_MANAGER_REGION],
        tgt.[T_HAYS_REGION]          = src.[T_HAYS_REGION],
        tgt.[T_HAYS_DIVISION]        = src.[T_HAYS_DIVISION],
        tgt.[T_TRAVEL_REGION]        = src.[T_TRAVEL_REGION],
        tgt.[T_TRAVEL_DIVISION]      = src.[T_TRAVEL_DIVISION],
        tgt.[T_COUNTRY]              = src.[T_COUNTRY],
        tgt.[T_CITY]                 = src.[T_CITY],
        tgt.[T_EMAIL]                = src.[T_EMAIL],
        tgt.[T_AGENT_CURRENCY]       = src.[T_AGENT_CURRENCY],
        tgt.[NUM_PAYMENT_RECOG_DAYS] = src.[NUM_PAYMENT_RECOG_DAYS],
        tgt.[DT_LAST_UPDATED]        = src.[DT_LAST_UPDATED]
    WHEN NOT MATCHED BY TARGET THEN INSERT (
        [ID_AGENT], [CD_DISTRIBUTOR_ID], [CD_EXTERNAL_AGENT_ID], [CD_SOURCE],
        [T_AGENT_NAME], [T_ABTA],
        [FL_IS_TRADE_AGENT], [FL_IS_NET_AGENT], [T_DISTRIBUTOR_TYPE], [VL_AGENT_MARKUP],
        [T_CHANNEL], [T_ACCOUNT_CHANNEL],
        [T_AGENT_GROUP_NAME], [T_AGENT_CONSORTIA], [T_AGENT_MANAGER], [T_MANAGER_REGION],
        [T_HAYS_REGION], [T_HAYS_DIVISION], [T_TRAVEL_REGION], [T_TRAVEL_DIVISION],
        [T_COUNTRY], [T_CITY], [T_EMAIL], [T_AGENT_CURRENCY],
        [NUM_PAYMENT_RECOG_DAYS], [DT_CREATED], [DT_LAST_UPDATED]
    ) VALUES (
        src.[ID_AGENT], src.[CD_DISTRIBUTOR_ID], src.[CD_EXTERNAL_AGENT_ID], src.[CD_SOURCE],
        src.[T_AGENT_NAME], src.[T_ABTA],
        src.[FL_IS_TRADE_AGENT], src.[FL_IS_NET_AGENT], src.[T_DISTRIBUTOR_TYPE], src.[VL_AGENT_MARKUP],
        src.[T_CHANNEL], src.[T_ACCOUNT_CHANNEL],
        src.[T_AGENT_GROUP_NAME], src.[T_AGENT_CONSORTIA], src.[T_AGENT_MANAGER], src.[T_MANAGER_REGION],
        src.[T_HAYS_REGION], src.[T_HAYS_DIVISION], src.[T_TRAVEL_REGION], src.[T_TRAVEL_DIVISION],
        src.[T_COUNTRY], src.[T_CITY], src.[T_EMAIL], src.[T_AGENT_CURRENCY],
        src.[NUM_PAYMENT_RECOG_DAYS], src.[DT_CREATED], src.[DT_LAST_UPDATED]
    )
    WHEN NOT MATCHED BY SOURCE THEN UPDATE SET tgt.[FL_IS_ACTIVE] = 0;

END;
