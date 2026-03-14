/*
================================================================================
 Table: L1_DIM_CHANNEL
 Layer: Gold (L1)
 Source: L0_SRG_CHANNEL
================================================================================
*/

CREATE TABLE [L1_DIM_CHANNEL] (

    [ID_CHANNEL]                INT            NOT NULL,
    [CD_CHANNEL_TYPE]           NVARCHAR(100)  NULL,   -- B2C, B2B, Marketplace
    [T_CHANNEL_NAME]            NVARCHAR(255)  NULL,
    [T_SALEDESK_NAME]           NVARCHAR(255)  NULL,

    [DT_CREATED]                DATETIME2(0)   NULL,
    [DT_LAST_UPDATED]           DATETIME2(0)   NULL,

    CONSTRAINT [PK_L1_DIM_CHANNEL] PRIMARY KEY CLUSTERED ([ID_CHANNEL] ASC)
);
