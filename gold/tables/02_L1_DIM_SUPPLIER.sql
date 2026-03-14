/*
================================================================================
 Table: L1_DIM_SUPPLIER
 Layer: Gold (L1)
 Source: L0_SRG_SUPPLIER, MD_LIST_PRODUCTS (for enrichment)
 Old equivalent: DimSupplier (combined view attributes)
================================================================================
*/

CREATE TABLE [L1_DIM_SUPPLIER] (

    [ID_SUPPLIER]               INT            NOT NULL,   -- FK from L0_SRG_SUPPLIER.ID_SUPPLIER
    [CD_SUPPLIER_ID]            INT            NOT NULL,   -- Prio Supplier_ID
    [CD_SOURCE]                 NVARCHAR(50)   NOT NULL DEFAULT 'PRIO',

    [T_SUPPLIER_NAME]           NVARCHAR(500)  NULL,
    [T_SUPPLIER_GROUP]          NVARCHAR(150)  NULL,
    [T_PRODUCT_MANAGER]         NVARCHAR(100)  NULL,
    [T_SUPPLIER_SET]            NVARCHAR(100)  NULL,
    [T_CATEGORY]                NVARCHAR(100)  NULL,

    [FL_IS_PACKAGE_SUPPLIER]    BIT            NULL DEFAULT 0,
    [FL_IS_ACTIVE]              BIT            NULL DEFAULT 1,

    [DT_CREATED]                DATETIME2(0)   NULL,
    [DT_LAST_UPDATED]           DATETIME2(0)   NULL,

    CONSTRAINT [PK_L1_DIM_SUPPLIER] PRIMARY KEY CLUSTERED ([ID_SUPPLIER] ASC)
);
