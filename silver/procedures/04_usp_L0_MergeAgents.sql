/*
================================================================================
 Procedure: usp_L0_MergeAgents
 Layer: Silver (L0)
 Source: L0_PRIO_SALES_TRANSACTION (unprocessed rows)
 Target: L0_SRG_AGENT
 Old equivalent: usp_ProcessGeneralDimensions (Agents section)
================================================================================
 Purpose:
   MERGE new and updated agent/distributor records into L0_SRG_AGENT.
   Agent name from Prio is upserted; classification attributes (FL_IS_TRADE_AGENT,
   FL_IS_NET_AGENT, T_DISTRIBUTOR_TYPE, T_CHANNEL, etc.) are set via the
   MD_LIST_AGENTS SharePoint sync (separate pipeline), not here.
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L0_MergeAgents]
AS
BEGIN
    SET NOCOUNT ON;

    WITH NewAgents AS (
        SELECT
            CAST(CD_DISTRIBUTOR_ID AS INT) AS CD_DISTRIBUTOR_ID,
            MAX(T_DISTRIBUTOR_NAME)         AS T_DISTRIBUTOR_NAME
        FROM [L0_PRIO_SALES_TRANSACTION]
        WHERE
            FL_IS_PROCESSED = 0
            AND CD_TRANSACTION_VERSION <> ''
        GROUP BY CD_DISTRIBUTOR_ID
    )
    MERGE [L0_SRG_AGENT] AS tgt
    USING NewAgents AS src
        ON tgt.[CD_DISTRIBUTOR_ID] = src.CD_DISTRIBUTOR_ID
        AND tgt.[CD_SOURCE] = 'PRIO'

    WHEN MATCHED AND tgt.[T_AGENT_NAME] <> src.T_DISTRIBUTOR_NAME THEN
        UPDATE SET
            [T_AGENT_NAME]    = src.T_DISTRIBUTOR_NAME,
            [DT_LAST_UPDATED] = SYSDATETIME()

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            [ID_AGENT],
            [CD_DISTRIBUTOR_ID],
            [CD_SOURCE],
            [T_AGENT_NAME],
            [FL_USE_PRIO_NAME],
            [FL_IS_TRADE_AGENT],   -- Default FALSE; set by MD_LIST_AGENTS SharePoint sync
            [DT_CREATED],
            [DT_LAST_UPDATED]
        )
        VALUES (
            ISNULL((SELECT MAX(ID_AGENT) FROM L0_SRG_AGENT), 0) + 1,
            src.CD_DISTRIBUTOR_ID,
            'PRIO',
            src.T_DISTRIBUTOR_NAME,
            1,
            0,
            SYSDATETIME(),
            SYSDATETIME()
        );

END;
