/*
================================================================================
 Table: L0_SRG_PRODUCT
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION, MD_LIST_PRODUCTS (SharePoint)
 Old equivalent: DimProduct
================================================================================
 Purpose:
   Incremental surrogate key generation for the Product dimension.
   Business key: CD_PRODUCT_ID + CD_SUPPLIER_ID + CD_SOURCE.
   Implements SCD Type 1 for name/category updates.
   AW-curated overrides (city/region/country/category) are applied from
   the MD_LIST_PRODUCTS SharePoint list during the Gold load.
================================================================================
*/

CREATE TABLE [L0_SRG_PRODUCT] (

    -- Surrogate key
    [ID_PRODUCT]                INT            NOT NULL,   -- Surrogate PK

    -- Business / natural key
    [CD_PRODUCT_ID]             INT            NOT NULL,   -- Source product ID
    [CD_SUPPLIER_ID]            INT            NOT NULL,   -- Supplier ID (product belongs to one supplier)
    [CD_SOURCE]                 NVARCHAR(50)   NOT NULL DEFAULT 'PRIO',

    -- FK to supplier surrogation
    [ID_SUPPLIER]               INT            NULL,       -- FK → L0_SRG_SUPPLIER.ID_SUPPLIER

    -- Product attributes (from Prio)
    [T_PRODUCT_NAME]            NVARCHAR(500)  NULL,       -- Product name (longest observed from transactions)
    [FL_USE_PRIO_NAME]          BIT            NULL DEFAULT 1,
    [FL_IS_PACKAGE]             BIT            NULL DEFAULT 0,  -- TRUE if product belongs to package supplier

    -- Geography attributes (from Prio / overridden by SharePoint)
    [T_PRODUCT_CITY]            NVARCHAR(255)  NULL,
    [T_PRODUCT_REGION]          NVARCHAR(255)  NULL,
    [T_PRODUCT_COUNTRY]         NVARCHAR(255)  NULL,

    -- AW override geography (from MD_LIST_PRODUCTS SharePoint)
    [T_AW_PRODUCT_CITY]         NVARCHAR(255)  NULL,
    [T_AW_PRODUCT_REGION]       NVARCHAR(255)  NULL,
    [T_AW_PRODUCT_COUNTRY]      NVARCHAR(255)  NULL,
    [T_PRODUCT_CATEGORY]        NVARCHAR(255)  NULL,
    [T_ADMIN_NAME]              NVARCHAR(100)  NULL,       -- Reporting admin / manager name
    [T_PRODUCT_TAG]             NVARCHAR(500)  NULL,

    -- Geography coordinates (optional)
    [T_LATITUDE]                NVARCHAR(50)   NULL,
    [T_LONGITUDE]               NVARCHAR(50)   NULL,

    -- Audit
    [DT_CREATED]                DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]           DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT [PK_L0_SRG_PRODUCT] PRIMARY KEY CLUSTERED ([ID_PRODUCT] ASC),
    CONSTRAINT [UQ_L0_SRG_PRODUCT_BK] UNIQUE ([CD_PRODUCT_ID], [CD_SUPPLIER_ID], [CD_SOURCE])
);
