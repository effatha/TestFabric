/*
================================================================================
 Table: L0_SRG_SUPPLIER
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION (Prio), MD_LIST_AGENTS (SharePoint overrides)
 Old equivalent: DimSupplier
================================================================================
 Purpose:
   Incremental surrogate key generation for the Supplier dimension.
   Supports multi-source surrogation via (CD_SUPPLIER_ID, CD_SOURCE) composite key.
   Implements SCD Type 1 (name updates) — supplier names are updated in-place
   as they may change in Prio without warranting a new history record.
================================================================================
 Key: ID_SUPPLIER (surrogate, auto-increment)
 Business Key: CD_SUPPLIER_ID + CD_SOURCE
================================================================================
*/

CREATE TABLE [L0_SRG_SUPPLIER] (

    -- Surrogate key (auto-increment)
    [ID_SUPPLIER]               INT            NOT NULL,   -- Surrogate PK

    -- Business / natural key
    [CD_SUPPLIER_ID]            INT            NOT NULL,   -- Source supplier ID (e.g. Prio Supplier_ID)
    [CD_SOURCE]                 NVARCHAR(50)   NOT NULL DEFAULT 'PRIO',  -- Source system identifier

    -- Attributes
    [T_SUPPLIER_NAME]           NVARCHAR(500)  NULL,       -- Supplier name (from Prio / overridden by SharePoint)
    [FL_USE_PRIO_NAME]          BIT            NULL DEFAULT 1,  -- 1=use Prio name, 0=use AW override name
    [FL_IS_PACKAGE_SUPPLIER]    BIT            NULL DEFAULT 0,  -- Marks suppliers that only appear in packages
    [T_SUPPLIER_GROUP]          NVARCHAR(150)  NULL,       -- Supplier grouping (e.g. "Disney", "Merlin")
    [T_PRODUCT_MANAGER]         NVARCHAR(100)  NULL,       -- AW product manager responsible
    [T_SUPPLIER_SET]            NVARCHAR(100)  NULL,       -- Supplier set classification
    [T_CATEGORY]                NVARCHAR(100)  NULL,       -- Product category

    -- Audit
    [DT_CREATED]                DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]           DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT [PK_L0_SRG_SUPPLIER] PRIMARY KEY CLUSTERED ([ID_SUPPLIER] ASC),
    CONSTRAINT [UQ_L0_SRG_SUPPLIER_BK] UNIQUE ([CD_SUPPLIER_ID], [CD_SOURCE])
);
