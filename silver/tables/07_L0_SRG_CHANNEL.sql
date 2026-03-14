/*
================================================================================
 Table: L0_SRG_CHANNEL
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION (Channel_Type, Channel_Name), MD_LIST_AGENTS
 Old equivalent: AgentChannels (partial)
================================================================================
 Purpose:
   Surrogate key table for the Channel dimension.
   Channels identify the sales channel type (B2C Direct, B2B Trade, Marketplace, etc.)
   and are populated from Prio transaction data and agent settings.
   Allows surrogation from multiple sources via (CD_CHANNEL_ID, CD_SOURCE).
================================================================================
*/

CREATE TABLE [L0_SRG_CHANNEL] (

    [ID_CHANNEL]                 INT             NOT NULL,
    [CD_CHANNEL_ID]              NVARCHAR(100)   NOT NULL,   -- Source channel identifier
    [CD_SOURCE]                  NVARCHAR(50)    NOT NULL DEFAULT 'PRIO',
    [CD_CHANNEL_TYPE]            NVARCHAR(100)   NULL,       -- Channel_Type from Prio (B2C, B2B, Marketplace)
    [T_CHANNEL_NAME]             NVARCHAR(255)   NULL,       -- Channel_Name from Prio
    [T_SALEDESK_NAME]            NVARCHAR(255)   NULL,

    [DT_CREATED]                 DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]            DATETIME2(0)    NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT [PK_L0_SRG_CHANNEL] PRIMARY KEY CLUSTERED ([ID_CHANNEL] ASC),
    CONSTRAINT [UQ_L0_SRG_CHANNEL_BK] UNIQUE ([CD_CHANNEL_ID], [CD_SOURCE])
);
