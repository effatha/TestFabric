/*
================================================================================
 Table: L0_REF_INVOICE_STATUS
 Layer: Silver (L0) - Reference / Lookup
 Source: Manual (static lookup) - migrated from DimInvoiceStatus + DimInvoiceTypes
 Old equivalent: DimInvoiceStatus + DimInvoiceTypes
================================================================================
 Purpose:
   Maps Invoice_Status strings from Prio CSV to normalised invoice types
   and debit/credit indicators. This is a static lookup table seeded once
   and maintained manually.
================================================================================
 Seed data: see INSERT statement at bottom of this file
================================================================================
*/

CREATE TABLE [L0_REF_INVOICE_STATUS] (

    [ID_INVOICE_STATUS]          INT             NOT NULL,   -- PK (maps to old nBookingSID)
    [CD_INVOICE_STATUS]          NVARCHAR(100)   NOT NULL,   -- e.g. 'Confirmed', 'Refunded'
    [T_INVOICE_TYPE]             NVARCHAR(50)    NOT NULL,   -- e.g. 'Revenue', 'Refunds', 'Discounts'
    [CD_TYPE_AMOUNT]             NCHAR(1)        NOT NULL,   -- 'D'=Debit, 'C'=Credit
    [CD_INVOICE_TID]             INT             NULL,       -- Legacy InvoiceTID reference
    [CD_INVOICE_SID]             INT             NULL,       -- Legacy InvoiceSID reference
    [FL_IS_ACTIVE]               BIT             NOT NULL DEFAULT 1,

    CONSTRAINT [PK_L0_REF_INVOICE_STATUS] PRIMARY KEY CLUSTERED ([ID_INVOICE_STATUS] ASC),
    CONSTRAINT [UQ_L0_REF_INVOICE_STATUS] UNIQUE ([CD_INVOICE_STATUS], [T_INVOICE_TYPE])
);

-- Seed data (migrated from old DimInvoiceStatus + DimInvoiceTypes)
INSERT INTO [L0_REF_INVOICE_STATUS] ([ID_INVOICE_STATUS], [CD_INVOICE_STATUS], [T_INVOICE_TYPE], [CD_TYPE_AMOUNT], [CD_INVOICE_TID], [CD_INVOICE_SID])
VALUES
    (2640, 'Confirmed',   'Revenue',       'D', 1855, 2640),
    (2660, 'Refunded',    'Refunds',        'C', 1855, 2660),
    (2661, 'Rebooked',    'Revenue',        'D', 1855, 2661),
    (3810, 'Confirmed',   'Discounts',      'D', 3810, 2640),
    (3811, 'Refunded',    'Discounts',      'C', 3810, 2660),
    (3880, 'Confirmed',   'Tour Commissions','C', 1855, 3880),
    (3881, 'Confirmed',   'VAT Commissions', 'C', 1855, 3881);
