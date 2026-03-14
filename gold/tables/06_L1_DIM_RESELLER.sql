/*
================================================================================
 Table: L1_DIM_RESELLER
 Layer: Gold (L1)
 Source: L0_SRG_RESELLER
================================================================================
*/

CREATE TABLE [L1_DIM_RESELLER] (

    [ID_RESELLER]               INT            NOT NULL,
    [CD_RESELLER_ID]            NVARCHAR(255)  NULL,
    [T_RESELLER_NAME]           NVARCHAR(500)  NULL,
    [CD_SOURCE]                 NVARCHAR(50)   NULL DEFAULT 'PRIO',

    [DT_CREATED]                DATETIME2(0)   NULL,
    [DT_LAST_UPDATED]           DATETIME2(0)   NULL,

    CONSTRAINT [PK_L1_DIM_RESELLER] PRIMARY KEY CLUSTERED ([ID_RESELLER] ASC)
);
