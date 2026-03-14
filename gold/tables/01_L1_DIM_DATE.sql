/*
================================================================================
 Table: L1_DIM_DATE
 Layer: Gold (L1)
 Source: Generated (no external source needed)
================================================================================
 Purpose:
   Standard date dimension for temporal analysis.
   Covers 2015-01-01 to 2035-12-31 (20 years).
   Supports fiscal year logic: FY starts 1st November.
================================================================================
*/

CREATE TABLE [L1_DIM_DATE] (

    [ID_DATE]               INT            NOT NULL,   -- PK: YYYYMMDD integer
    [DT_DATE]               DATE           NOT NULL,

    -- Calendar
    [NUM_DAY]               INT            NOT NULL,
    [NUM_WEEK]              INT            NOT NULL,   -- ISO week number
    [NUM_MONTH]             INT            NOT NULL,
    [NUM_QUARTER]           INT            NOT NULL,
    [NUM_YEAR]              INT            NOT NULL,
    [T_DAY_NAME]            NVARCHAR(20)   NOT NULL,   -- 'Monday', 'Tuesday', etc.
    [T_MONTH_NAME]          NVARCHAR(20)   NOT NULL,   -- 'January', etc.
    [T_MONTH_SHORT]         NVARCHAR(5)    NOT NULL,   -- 'Jan', 'Feb', etc.
    [T_QUARTER]             NVARCHAR(5)    NOT NULL,   -- 'Q1', 'Q2', etc.
    [FL_IS_WEEKEND]         BIT            NOT NULL DEFAULT 0,
    [FL_IS_UK_BANK_HOLIDAY] BIT            NOT NULL DEFAULT 0,

    -- Fiscal Year (November start)
    [T_FISCAL_YEAR]         NVARCHAR(20)   NOT NULL,   -- 'FY2025/2026'
    [NUM_FISCAL_YEAR]       INT            NOT NULL,   -- 2025 (start year of FY)
    [NUM_FISCAL_MONTH]      INT            NOT NULL,   -- 1=Nov, 2=Dec, ..., 12=Oct
    [NUM_FISCAL_QUARTER]    INT            NOT NULL,   -- FQ1=Nov-Jan, FQ2=Feb-Apr, etc.
    [T_FISCAL_QUARTER]      NVARCHAR(10)   NOT NULL,

    -- Rolling periods (relative to today)
    [FL_IS_CURRENT_YEAR]    BIT            NOT NULL DEFAULT 0,
    [FL_IS_CURRENT_MONTH]   BIT            NOT NULL DEFAULT 0,
    [FL_IS_CURRENT_WEEK]    BIT            NOT NULL DEFAULT 0,
    [FL_IS_TODAY]           BIT            NOT NULL DEFAULT 0,

    CONSTRAINT [PK_L1_DIM_DATE] PRIMARY KEY CLUSTERED ([ID_DATE] ASC)
);

-- Populate: insert dates from 2015-01-01 to 2035-12-31
WITH DateRange AS (
    SELECT CAST('2015-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM DateRange WHERE d < '2035-12-31'
)
INSERT INTO [L1_DIM_DATE] (
    [ID_DATE], [DT_DATE],
    [NUM_DAY], [NUM_WEEK], [NUM_MONTH], [NUM_QUARTER], [NUM_YEAR],
    [T_DAY_NAME], [T_MONTH_NAME], [T_MONTH_SHORT], [T_QUARTER],
    [FL_IS_WEEKEND],
    [T_FISCAL_YEAR], [NUM_FISCAL_YEAR], [NUM_FISCAL_MONTH], [NUM_FISCAL_QUARTER], [T_FISCAL_QUARTER]
)
SELECT
    CAST(FORMAT(d, 'yyyyMMdd') AS INT),
    d,
    DAY(d),
    DATEPART(ISO_WEEK, d),
    MONTH(d),
    DATEPART(QUARTER, d),
    YEAR(d),
    DATENAME(WEEKDAY, d),
    DATENAME(MONTH, d),
    LEFT(DATENAME(MONTH, d), 3),
    'Q' + CAST(DATEPART(QUARTER, d) AS NVARCHAR(1)),
    CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END,  -- Sun=1, Sat=7 (US convention)

    -- Fiscal year: FY starts 1 November
    'FY' + CAST(
        CASE WHEN MONTH(d) < 11 THEN YEAR(DATEADD(YEAR,-1,d)) ELSE YEAR(d) END
    AS NVARCHAR(4)) + '/' + CAST(
        CASE WHEN MONTH(d) < 11 THEN YEAR(d) ELSE YEAR(DATEADD(YEAR,1,d)) END
    AS NVARCHAR(4)),

    CASE WHEN MONTH(d) < 11 THEN YEAR(DATEADD(YEAR,-1,d)) ELSE YEAR(d) END,

    -- Fiscal month: Nov=1, Dec=2, Jan=3, ..., Oct=12
    CASE MONTH(d)
        WHEN 11 THEN 1  WHEN 12 THEN 2
        WHEN 1  THEN 3  WHEN 2  THEN 4
        WHEN 3  THEN 5  WHEN 4  THEN 6
        WHEN 5  THEN 7  WHEN 6  THEN 8
        WHEN 7  THEN 9  WHEN 8  THEN 10
        WHEN 9  THEN 11 WHEN 10 THEN 12
    END,

    -- Fiscal quarter: FQ1=Nov-Jan, FQ2=Feb-Apr, FQ3=May-Jul, FQ4=Aug-Oct
    CASE MONTH(d)
        WHEN 11 THEN 1 WHEN 12 THEN 1 WHEN 1 THEN 1
        WHEN 2  THEN 2 WHEN 3  THEN 2 WHEN 4 THEN 2
        WHEN 5  THEN 3 WHEN 6  THEN 3 WHEN 7 THEN 3
        WHEN 8  THEN 4 WHEN 9  THEN 4 WHEN 10 THEN 4
    END,
    'FQ' + CAST(CASE MONTH(d)
        WHEN 11 THEN 1 WHEN 12 THEN 1 WHEN 1 THEN 1
        WHEN 2  THEN 2 WHEN 3  THEN 2 WHEN 4 THEN 2
        WHEN 5  THEN 3 WHEN 6  THEN 3 WHEN 7 THEN 3
        WHEN 8  THEN 4 WHEN 9  THEN 4 WHEN 10 THEN 4
    END AS NVARCHAR(1))

FROM DateRange
OPTION (MAXRECURSION 8000);
