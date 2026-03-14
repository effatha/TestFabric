/*
================================================================================
 Table: L0_SRG_RESELLER
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION (Reseller_ID, Reseller_Name)
 Old equivalent: No direct equivalent (was embedded in FactPrioSales)
================================================================================
 Purpose:
   Surrogate key table for the Reseller dimension.
   Resellers are sub-agents or marketplaces that sit between the distributor
   and the end customer. They appear in the Prio transaction CSV.
================================================================================
*/

CREATE TABLE [L0_SRG_RESELLER] (

    [ID_RESELLER]                INT             NOT NULL,
    [CD_RESELLER_ID]             NVARCHAR(255)   NOT NULL,
    [CD_SOURCE]                  NVARCHAR(50)    NOT NULL DEFAULT 'PRIO',
    [T_RESELLER_NAME]            NVARCHAR(500)   NULL,

    [DT_CREATED]                 DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]            DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT [PK_L0_SRG_RESELLER] PRIMARY KEY CLUSTERED ([ID_RESELLER] ASC),
    CONSTRAINT [UQ_L0_SRG_RESELLER_BK] UNIQUE ([CD_RESELLER_ID], [CD_SOURCE])
);
