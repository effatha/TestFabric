/*
================================================================================
 Table: L1_DIM_PRODUCT
 Layer: Gold (L1)
 Source: L0_SRG_PRODUCT, MD_LIST_PRODUCTS (SharePoint enrichment)
 Old equivalent: DimProduct (combined with AW-override columns)
================================================================================
*/

CREATE TABLE [L1_DIM_PRODUCT] (

    [ID_PRODUCT]                INT            NOT NULL,   -- FK from L0_SRG_PRODUCT.ID_PRODUCT
    [ID_SUPPLIER]               INT            NULL,       -- FK → L1_DIM_SUPPLIER
    [CD_PRODUCT_ID]             INT            NOT NULL,
    [CD_SUPPLIER_ID]            INT            NOT NULL,
    [CD_SOURCE]                 NVARCHAR(50)   NOT NULL DEFAULT 'PRIO',

    -- Names
    [T_PRODUCT_NAME]            NVARCHAR(500)  NULL,       -- Effective name (Prio or AW override)
    [T_PRIO_PRODUCT_NAME]       NVARCHAR(500)  NULL,       -- Raw Prio name

    -- Geography: effective values (AW override wins over Prio)
    [T_PRODUCT_CITY]            NVARCHAR(255)  NULL,
    [T_PRODUCT_REGION]          NVARCHAR(255)  NULL,
    [T_PRODUCT_COUNTRY]         NVARCHAR(255)  NULL,
    [T_PRODUCT_CATEGORY]        NVARCHAR(255)  NULL,
    [T_ADMIN_NAME]              NVARCHAR(100)  NULL,
    [T_PRODUCT_TAG]             NVARCHAR(500)  NULL,

    -- Coordinates
    [T_LATITUDE]                NVARCHAR(50)   NULL,
    [T_LONGITUDE]               NVARCHAR(50)   NULL,

    [FL_IS_PACKAGE]             BIT            NULL DEFAULT 0,
    [FL_IS_ACTIVE]              BIT            NULL DEFAULT 1,

    [DT_CREATED]                DATETIME2(0)   NULL,
    [DT_LAST_UPDATED]           DATETIME2(0)   NULL,

    CONSTRAINT [PK_L1_DIM_PRODUCT] PRIMARY KEY CLUSTERED ([ID_PRODUCT] ASC)
);
