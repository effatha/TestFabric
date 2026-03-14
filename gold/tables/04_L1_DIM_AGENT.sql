/*
================================================================================
 Table: L1_DIM_AGENT
 Layer: Gold (L1)
 Source: L0_SRG_AGENT, MD_LIST_AGENTS (SharePoint enrichment)
 Old equivalent: DimAgent + vDimAgents view attributes
================================================================================
*/

CREATE TABLE [L1_DIM_AGENT] (

    [ID_AGENT]                  INT            NOT NULL,
    [CD_DISTRIBUTOR_ID]         INT            NOT NULL,
    [CD_EXTERNAL_AGENT_ID]      NVARCHAR(50)   NULL,
    [CD_SOURCE]                 NVARCHAR(50)   NOT NULL DEFAULT 'PRIO',

    -- Names
    [T_AGENT_NAME]              NVARCHAR(500)  NULL,
    [T_ABTA]                    NVARCHAR(50)   NULL,

    -- Classification
    [FL_IS_TRADE_AGENT]         BIT            NOT NULL DEFAULT 0,
    [FL_IS_NET_AGENT]           BIT            NULL DEFAULT 0,
    [T_DISTRIBUTOR_TYPE]        NVARCHAR(50)   NULL,   -- 'CostPlus', 'NetAgent', 'Standard'
    [VL_AGENT_MARKUP]           DECIMAL(19,4)  NULL,
    [T_CHANNEL]                 NVARCHAR(50)   NULL,   -- 'B2C', 'B2B', 'B2B2C'
    [T_ACCOUNT_CHANNEL]         NVARCHAR(150)  NULL,

    -- Grouping / hierarchy
    [T_AGENT_GROUP_NAME]        NVARCHAR(255)  NULL,
    [T_AGENT_CONSORTIA]         NVARCHAR(150)  NULL,
    [T_AGENT_MANAGER]           NVARCHAR(100)  NULL,
    [T_MANAGER_REGION]          NVARCHAR(100)  NULL,
    [T_HAYS_REGION]             NVARCHAR(100)  NULL,
    [T_HAYS_DIVISION]           NVARCHAR(100)  NULL,
    [T_TRAVEL_REGION]           NVARCHAR(150)  NULL,
    [T_TRAVEL_DIVISION]         NVARCHAR(150)  NULL,

    -- Contact
    [T_COUNTRY]                 NVARCHAR(150)  NULL,
    [T_CITY]                    NVARCHAR(150)  NULL,
    [T_EMAIL]                   NVARCHAR(150)  NULL,
    [T_AGENT_CURRENCY]          NVARCHAR(10)   NULL,

    -- Payment terms
    [NUM_PAYMENT_RECOG_DAYS]    INT            NULL DEFAULT 56,

    [FL_IS_ACTIVE]              BIT            NULL DEFAULT 1,
    [DT_CREATED]                DATETIME2(0)   NULL,
    [DT_LAST_UPDATED]           DATETIME2(0)   NULL,

    CONSTRAINT [PK_L1_DIM_AGENT] PRIMARY KEY CLUSTERED ([ID_AGENT] ASC)
);
