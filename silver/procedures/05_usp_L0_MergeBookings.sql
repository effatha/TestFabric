/*
================================================================================
 Procedure: usp_L0_MergeBookings
 Layer: Silver (L0)
 Source: L0_PRIO_SALES_TRANSACTION (unprocessed), L0_SRG_AGENT, WP_FTIX_TRANSACTIONS,
         WP_ATIX_TRANSACTIONS, PRIO_API_ORDERS (Bronze Lakehouse references)
 Target: L0_SRG_BOOKING
 Old equivalent: usp_ProcessBookings
================================================================================
 Purpose:
   Build and maintain the booking-level entity in Silver.
   A booking = one (Order_ID, Product_ID) combination.
   Logic:
     1. Derive booking status: Confirmed if ≥1 confirmed transaction, Refunded if all cancelled
     2. Insert new bookings
     3. Update existing bookings (status, departure date, version)
     4. Mark previous versions as not current (FL_IS_CURRENT_VERSION = 0)
     5. Enrich with LeadPaxName, Email from Prio Order API (Bronze)
     6. Override created date from WordPress (FTIX/ATIX) if applicable
     7. Attribute call-centre bookings (BookedBy) from cc tables
================================================================================
*/

CREATE PROCEDURE [dbo].[usp_L0_MergeBookings]
AS
BEGIN
    SET NOCOUNT ON;

    /*
    ============================================================
    STEP 1: Stage booking candidates from unprocessed transactions
    ============================================================
    */
    DROP TABLE IF EXISTS #BookingStage;

    CREATE TABLE #BookingStage (
        CD_ORDER_ID         NVARCHAR(255),
        CD_PRODUCT_ID       INT,
        CD_DISTRIBUTOR_ID   INT,
        DT_CREATED          DATETIME2(0),
        DT_DEPARTURE        DATETIME2(0),
        CD_BOOKING_STATUS   NVARCHAR(50),
        VL_VERSION          FLOAT,
        T_PACKAGE_TYPE      NVARCHAR(50),
        CD_CLIENT_REFERENCE NVARCHAR(255)
    );

    WITH BookingStatus AS (
        SELECT
            CD_ORDER_ID,
            CAST(CD_PRODUCT_ID AS INT) AS CD_PRODUCT_ID,
            SUM(CASE WHEN CD_INVOICE_STATUS = 'Confirmed' THEN 1 ELSE 0 END) AS HasConfirmed,
            SUM(CASE WHEN CD_INVOICE_STATUS = 'Refunded'  THEN 1 ELSE 0 END) AS HasRefund
        FROM [L0_PRIO_SALES_TRANSACTION]
        WHERE FL_IS_PROCESSED = 0
        GROUP BY CD_ORDER_ID, CAST(CD_PRODUCT_ID AS INT)
    )
    INSERT INTO #BookingStage
    SELECT DISTINCT
        t.CD_ORDER_ID,
        t.CD_PRODUCT_ID,
        t.CD_DISTRIBUTOR_ID,
        -- Created date: earlier of transaction date and order creation date
        MIN(CASE WHEN t.DT_CREATED > t.DT_TRANSACTION THEN t.DT_TRANSACTION ELSE t.DT_CREATED END) AS DT_CREATED,
        MIN(TRY_CAST(t.DT_RESERVATION AS DATETIME2(0)))                                              AS DT_DEPARTURE,
        -- Status: Confirmed wins if any confirmed exist; Refunded only if all cancelled
        CASE
            WHEN bs.HasRefund > 0 AND (bs.HasConfirmed = 0 OR bs.HasRefund = bs.HasConfirmed) THEN 'Cancelled'
            WHEN bs.HasConfirmed > 0 AND (bs.HasRefund = 0 OR bs.HasRefund < bs.HasConfirmed) THEN 'Confirmed'
            ELSE 'NA'
        END AS CD_BOOKING_STATUS,
        MAX(TRY_CAST(t.CD_TRANSACTION_VERSION AS FLOAT))                                             AS VL_VERSION,
        -- Package type (mirrors old logic)
        CASE
            WHEN t.T_COMBI_TYPE = 'Cluster' THEN 'PackageTicket'
            WHEN EXISTS (
                SELECT 1 FROM [L0_PRIO_SALES_TRANSACTION] t2
                WHERE t2.CD_ORDER_ID = t.CD_ORDER_ID AND t2.T_COMBI_TYPE = 'Cluster'
            ) AND p.FL_IS_PACKAGE = 1 THEN 'Package'
            ELSE 'Single Ticket'
        END,
        MAX(t.CD_CLIENT_REFERENCE_NO)
    FROM [L0_PRIO_SALES_TRANSACTION] t
    INNER JOIN BookingStatus bs ON bs.CD_ORDER_ID = t.CD_ORDER_ID AND bs.CD_PRODUCT_ID = t.CD_PRODUCT_ID
    LEFT JOIN [L0_SRG_PRODUCT] p ON p.CD_PRODUCT_ID = t.CD_PRODUCT_ID AND p.CD_SOURCE = 'PRIO'
    WHERE
        t.FL_IS_PROCESSED = 0
        AND t.DT_RESERVATION IS NOT NULL
        AND t.DT_CREATED IS NOT NULL
        AND LEN(ISNULL(CAST(t.DT_RESERVATION AS NVARCHAR(20)), '')) = 10
    GROUP BY
        t.CD_ORDER_ID, t.CD_PRODUCT_ID, t.CD_DISTRIBUTOR_ID, t.T_COMBI_TYPE, p.FL_IS_PACKAGE,
        bs.HasConfirmed, bs.HasRefund;

    /*
    ============================================================
    STEP 2: UPDATE existing bookings
    ============================================================
    */
    UPDATE b
    SET
        b.[T_BOOKING_TYPE]       = CASE WHEN a.[FL_IS_TRADE_AGENT] = 1 THEN 'Trade' ELSE 'Direct' END,
        b.[DT_DEPARTURE]         = s.DT_DEPARTURE,
        b.[VL_VERSION]           = s.VL_VERSION,
        b.[CD_EXT_BOOKING_REFERENCE] = s.CD_CLIENT_REFERENCE,
        b.[T_BOOKING_STATUS]     = s.CD_BOOKING_STATUS,
        b.[CD_BOOKING_STATUS]    = CASE s.CD_BOOKING_STATUS WHEN 'Confirmed' THEN 2640 WHEN 'Cancelled' THEN 2660 ELSE 2661 END,
        b.[DT_CREATED]           = s.DT_CREATED,
        b.[DT_LAST_UPDATED]      = SYSDATETIME()
    FROM [L0_SRG_BOOKING] b
    INNER JOIN #BookingStage s   ON s.CD_ORDER_ID = b.CD_ORDER_ID AND s.CD_PRODUCT_ID = b.CD_PRODUCT_ID
    INNER JOIN [L0_SRG_AGENT] a  ON a.CD_DISTRIBUTOR_ID = s.CD_DISTRIBUTOR_ID AND a.CD_SOURCE = 'PRIO';

    /*
    ============================================================
    STEP 3: INSERT new bookings
    ============================================================
    */
    INSERT INTO [L0_SRG_BOOKING] (
        [ID_BOOKING], [CD_ORDER_ID], [CD_PRODUCT_ID], [CD_SOURCE],
        [ID_AGENT], [CD_BOOKING_STATUS], [T_BOOKING_STATUS], [T_BOOKING_TYPE],
        [T_BOOKING_SOURCE], [T_PACKAGE_TYPE],
        [DT_CREATED], [DT_DEPARTURE],
        [VL_VERSION], [FL_IS_CURRENT_VERSION], [FL_IS_PRIO_BOOKING],
        [CD_EXT_BOOKING_REFERENCE], [T_FISCAL_YEAR]
    )
    SELECT
        ISNULL((SELECT MAX(ID_BOOKING) FROM L0_SRG_BOOKING), 0)
            + ROW_NUMBER() OVER (ORDER BY s.CD_ORDER_ID, s.CD_PRODUCT_ID),
        s.CD_ORDER_ID,
        s.CD_PRODUCT_ID,
        'PRIO',
        a.[ID_AGENT],
        CASE s.CD_BOOKING_STATUS WHEN 'Confirmed' THEN 2640 WHEN 'Cancelled' THEN 2660 ELSE 2661 END,
        s.CD_BOOKING_STATUS,
        CASE WHEN a.[FL_IS_TRADE_AGENT] = 1 THEN 'Trade' ELSE 'Direct' END,
        'PrioTicket',
        s.T_PACKAGE_TYPE,
        s.DT_CREATED,
        s.DT_DEPARTURE,
        s.VL_VERSION,
        1,
        1,
        s.CD_CLIENT_REFERENCE,
        -- Fiscal year: FY starts November
        'FY' + CAST(
            CASE WHEN MONTH(s.DT_DEPARTURE) < 11 THEN YEAR(DATEADD(YEAR,-1,s.DT_DEPARTURE))
                 ELSE YEAR(s.DT_DEPARTURE) END
        AS NVARCHAR(4))
        + '/' + CAST(
            CASE WHEN MONTH(s.DT_DEPARTURE) < 11 THEN YEAR(s.DT_DEPARTURE)
                 ELSE YEAR(DATEADD(YEAR,1,s.DT_DEPARTURE)) END
        AS NVARCHAR(4))
    FROM #BookingStage s
    INNER JOIN [L0_SRG_AGENT] a ON a.CD_DISTRIBUTOR_ID = s.CD_DISTRIBUTOR_ID AND a.CD_SOURCE = 'PRIO'
    LEFT JOIN [L0_SRG_BOOKING] b ON b.CD_ORDER_ID = s.CD_ORDER_ID AND b.CD_PRODUCT_ID = s.CD_PRODUCT_ID
    WHERE b.[ID_BOOKING] IS NULL;

    /*
    ============================================================
    STEP 4: Mark previous versions as not current
    ============================================================
    */
    WITH BookingCurrentVersion AS (
        SELECT CD_ORDER_ID, CD_PRODUCT_ID, MAX(TRY_CAST(CD_TRANSACTION_VERSION AS FLOAT)) AS MaxVersion
        FROM [L0_PRIO_SALES_TRANSACTION]
        WHERE FL_IS_PROCESSED = 0
        GROUP BY CD_ORDER_ID, CD_PRODUCT_ID
    )
    UPDATE b
        SET b.[FL_IS_CURRENT_VERSION] = 0
    FROM [L0_SRG_BOOKING] b
    INNER JOIN BookingCurrentVersion v
        ON v.CD_ORDER_ID = b.CD_ORDER_ID
        AND v.CD_PRODUCT_ID = b.CD_PRODUCT_ID
        AND v.MaxVersion > b.VL_VERSION;

    /*
    ============================================================
    STEP 5: Enrich with first departure date per order
    ============================================================
    */
    WITH FirstDeparture AS (
        SELECT CD_ORDER_ID, MIN(DT_DEPARTURE) AS DT_FIRST_DEPARTURE
        FROM [L0_SRG_BOOKING]
        WHERE FL_IS_CURRENT_VERSION = 1
        GROUP BY CD_ORDER_ID
    )
    UPDATE b
        SET b.[DT_FIRST_DEPARTURE] = fd.DT_FIRST_DEPARTURE
    FROM [L0_SRG_BOOKING] b
    INNER JOIN FirstDeparture fd ON fd.CD_ORDER_ID = b.CD_ORDER_ID;

    /*
    ============================================================
    STEP 6: Enrich Lead Pax Name + Email from Bronze PRIO_API_ORDERS
    ============================================================
    */
    MERGE [L0_SRG_BOOKING] AS tgt
    USING (
        SELECT CD_ORDER_ID, Partner_Name, Partner_Email
        FROM [BRONZE].[PRIO_API_ORDERS]
        WHERE NULLIF(TRIM(Partner_Name), '') IS NOT NULL
        GROUP BY CD_ORDER_ID, Partner_Name, Partner_Email
    ) AS src ON tgt.CD_ORDER_ID = src.CD_ORDER_ID AND tgt.T_LEAD_PAX_NAME IS NULL
    WHEN MATCHED THEN UPDATE SET
        tgt.[T_LEAD_PAX_NAME] = src.Partner_Name,
        tgt.[T_EMAIL]         = src.Partner_Email;

    /*
    ============================================================
    STEP 7: Override created date from FTIX WordPress
    ============================================================
    */
    UPDATE b
        SET b.[DT_CREATED] = wp.DT_WP_CREATED
    FROM [L0_SRG_BOOKING] b
    INNER JOIN (
        SELECT [Prio_Reservation_Id], MIN([date_created_gmt]) AS DT_WP_CREATED
        FROM [BRONZE].[WP_FTIX_TRANSACTIONS]
        GROUP BY [Prio_Reservation_Id]
    ) wp ON b.CD_ORDER_ID = wp.Prio_Reservation_Id;

    /*
    ============================================================
    STEP 8: Attribution of Call Centre bookings (FTIX + ATIX)
    ============================================================
    */
    MERGE [L0_SRG_BOOKING] AS tgt
    USING [BRONZE].[WP_FTIX_CC] AS src
        ON tgt.CD_ORDER_ID = CAST(src.PrioID AS NVARCHAR(255))
    WHEN MATCHED THEN UPDATE SET
        tgt.[T_BOOKING_SOURCE] = 'Call Centre',
        tgt.[T_BOOKED_BY]      = src.display_name;

    MERGE [L0_SRG_BOOKING] AS tgt
    USING [BRONZE].[WP_ATIX_CC] AS src
        ON tgt.CD_ORDER_ID = CAST(src.PrioID AS NVARCHAR(255))
    WHEN MATCHED THEN UPDATE SET
        tgt.[T_BOOKING_SOURCE] = 'Call Centre',
        tgt.[T_BOOKED_BY]      = src.display_name;

    DROP TABLE IF EXISTS #BookingStage;

END;
