/*
================================================================================
 Table: L0_SRG_BOOKING
 Layer: Silver (L0) - Surrogation
 Source: L0_PRIO_SALES_TRANSACTION, WP_FTIX_TRANSACTIONS, WP_ATIX_TRANSACTIONS, PRIO_API_ORDERS
 Old equivalent: DimBooking
================================================================================
 Purpose:
   Surrogate key and conformed booking-level entity.
   A booking = one Order_ID + Product_ID combination (a line in a Prio order).
   Tracks departure date, booking status, agent attribution, and enrichment
   data from WordPress and Prio Order API.
   Supports SCD Type 1 — status and dates updated in place.
   IsCurrentVersion flag marks the latest version when Prio sends updates.
================================================================================
 Key: ID_BOOKING (surrogate)
 Business Key: CD_ORDER_ID + CD_PRODUCT_ID + CD_SOURCE
================================================================================
*/

CREATE TABLE [L0_SRG_BOOKING] (

    -- Surrogate key
    [ID_BOOKING]                 INT             NOT NULL,   -- Surrogate PK

    -- Business / natural key
    [CD_ORDER_ID]                NVARCHAR(255)   NOT NULL,   -- Prio Order_ID
    [CD_PRODUCT_ID]              INT             NOT NULL,   -- Product within the order
    [CD_SOURCE]                  NVARCHAR(50)    NOT NULL DEFAULT 'PRIO',

    -- FK references (Silver surrogation)
    [ID_AGENT]                   INT             NULL,       -- FK → L0_SRG_AGENT.ID_AGENT

    -- Booking status
    [CD_BOOKING_STATUS]          INT             NULL,       -- Status SID (2640=Confirmed, 2660=Cancelled, 2661=Rebooked)
    [T_BOOKING_STATUS]           NVARCHAR(50)    NULL,       -- 'Confirmed', 'Cancelled', 'Rebooked'
    [T_BOOKING_TYPE]             NVARCHAR(50)    NULL,       -- 'Trade' (B2B) / 'Direct' (B2C)
    [T_BOOKING_SOURCE]           NVARCHAR(100)   NULL,       -- 'PrioTicket', 'Call Centre', 'FloridaTix', 'AttractionTix'
    [T_PACKAGE_TYPE]             NVARCHAR(50)    NULL,       -- 'Single Ticket', 'Package', 'PackageTicket'

    -- Dates
    [DT_CREATED]                 DATETIME2(0)    NULL,       -- Order creation date/time
    [DT_DEPARTURE]               DATETIME2(0)    NULL,       -- Departure/visit date
    [DT_FIRST_DEPARTURE]         DATETIME2(0)    NULL,       -- First departure across all products in the order
    [DT_CANCELLATION]            DATETIME2(0)    NULL,       -- Cancellation date (if cancelled)
    [DT_FULFILLMENT]             DATE            NULL,       -- Fulfillment date (combo tickets)

    -- Versioning
    [VL_VERSION]                 FLOAT           NULL,       -- Transaction version number
    [FL_IS_CURRENT_VERSION]      BIT             NULL DEFAULT 1,  -- Latest version flag
    [FL_IS_PRIO_BOOKING]         BIT             NULL DEFAULT 1,  -- TRUE for Prio source bookings
    [FL_IS_CLOSED]               BIT             NULL DEFAULT 0,  -- Closed/archived booking

    -- Customer enrichment (from Prio Order API)
    [T_LEAD_PAX_NAME]            NVARCHAR(255)   NULL,       -- Lead passenger / customer name
    [T_EMAIL]                    NVARCHAR(250)   NULL,       -- Customer email

    -- Cross-references
    [CD_EXT_BOOKING_REFERENCE]   NVARCHAR(100)   NULL,       -- External reference (from combo shell booking)
    [T_DISCOUNT_CODE]            NVARCHAR(50)    NULL,       -- Discount code applied
    [T_BOOKED_BY]                NVARCHAR(50)    NULL,       -- Call centre agent who made the booking

    -- Financial tracking
    [AMT_DEBTOR_BALANCE]         MONEY           NULL,       -- Outstanding debtor balance
    [FL_HAVE_PRIO_COMMISSION]    BIT             NULL,

    -- Fiscal year (computed, based on departure date: FY starts Nov)
    [T_FISCAL_YEAR]              NVARCHAR(20)    NULL,       -- e.g. 'FY2025/2026'

    -- Audit
    [DT_LAST_UPDATED]            DATETIME2(0)    NULL DEFAULT SYSDATETIME(),

    CONSTRAINT [PK_L0_SRG_BOOKING] PRIMARY KEY CLUSTERED ([ID_BOOKING] ASC),
    CONSTRAINT [UQ_L0_SRG_BOOKING_BK] UNIQUE ([CD_ORDER_ID], [CD_PRODUCT_ID], [CD_SOURCE])
);

CREATE INDEX [IX_L0_SRG_BOOKING_ORDER_ID]
    ON [L0_SRG_BOOKING] ([CD_ORDER_ID] ASC)
    INCLUDE ([CD_PRODUCT_ID], [ID_BOOKING], [FL_IS_CURRENT_VERSION]);
