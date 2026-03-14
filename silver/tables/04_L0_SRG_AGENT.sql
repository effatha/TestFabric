/*
================================================================================
 Table: L0_SRG_AGENT
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION, MD_LIST_AGENTS (SharePoint)
 Old equivalent: DimAgent
================================================================================
 Purpose:
   Incremental surrogate key generation for the Agent/Distributor dimension.
   Business key: CD_DISTRIBUTOR_ID + CD_SOURCE.
   Agent classification attributes (Trade/Net/CostPlus) are managed via
   the MD_LIST_AGENTS SharePoint list, which acts as the master reference.
   SCD Type 1 — attributes updated in-place.
================================================================================
*/

CREATE TABLE [L0_SRG_AGENT] (

    -- Surrogate key
    [ID_AGENT]                  INT            NOT NULL,   -- Surrogate PK

    -- Business / natural key
    [CD_DISTRIBUTOR_ID]         INT            NOT NULL,   -- Source distributor/agent ID
    [CD_SOURCE]                 NVARCHAR(50)   NOT NULL DEFAULT 'PRIO',
    [CD_EXTERNAL_AGENT_ID]      NVARCHAR(50)   NULL,       -- External system ID (cross-reference to Traveller)

    -- Agent identity
    [T_AGENT_NAME]              NVARCHAR(500)  NULL,       -- Agent name (from Prio)
    [FL_USE_PRIO_NAME]          BIT            NULL DEFAULT 1,
    [T_ABTA]                    NVARCHAR(50)   NULL,       -- ABTA number

    -- Classification (from MD_LIST_AGENTS SharePoint)
    [FL_IS_TRADE_AGENT]         BIT            NOT NULL DEFAULT 0,  -- B2B agent (TRUE) vs direct/B2C (FALSE)
    [FL_IS_NET_AGENT]           BIT            NULL DEFAULT 0,      -- Net pricing agent (commission subtracted from sale)
    [T_DISTRIBUTOR_TYPE]        NVARCHAR(50)   NULL,               -- 'CostPlus', 'NetAgent', 'Standard'
    [VL_AGENT_MARKUP]           DECIMAL(19,4)  NULL,               -- Markup % for CostPlus agents
    [T_CHANNEL]                 NVARCHAR(50)   NULL,               -- 'B2C', 'B2B', 'B2B2C'
    [T_ACCOUNT_CHANNEL]         NVARCHAR(150)  NULL,

    -- Agent grouping / hierarchies
    [T_AGENT_GROUP_NAME]        NVARCHAR(255)  NULL,
    [T_AGENT_CONSORTIA]         NVARCHAR(150)  NULL,
    [T_AGENT_MANAGER]           NVARCHAR(100)  NULL,
    [T_MANAGER_REGION]          NVARCHAR(100)  NULL,
    [T_HAYS_REGION]             NVARCHAR(100)  NULL,
    [T_HAYS_DIVISION]           NVARCHAR(100)  NULL,
    [T_TRAVEL_REGION]           NVARCHAR(150)  NULL,
    [T_TRAVEL_DIVISION]         NVARCHAR(150)  NULL,

    -- Contact / address
    [T_ADDRESS]                 NVARCHAR(MAX)  NULL,
    [T_COUNTRY]                 NVARCHAR(150)  NULL,
    [T_CITY]                    NVARCHAR(150)  NULL,
    [T_POSTAL_CODE]             NVARCHAR(50)   NULL,
    [T_EMAIL]                   NVARCHAR(150)  NULL,
    [T_PHONE]                   NVARCHAR(150)  NULL,
    [T_AGENT_CURRENCY]          NVARCHAR(10)   NULL,

    -- Payment terms
    [NUM_PAYMENT_RECOG_DAYS]    INT            NULL DEFAULT 56,    -- Days before revenue is recognised

    -- Audit
    [DT_CREATED]                DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    [DT_LAST_UPDATED]           DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT [PK_L0_SRG_AGENT] PRIMARY KEY CLUSTERED ([ID_AGENT] ASC),
    CONSTRAINT [UQ_L0_SRG_AGENT_BK] UNIQUE ([CD_DISTRIBUTOR_ID], [CD_SOURCE])
);
