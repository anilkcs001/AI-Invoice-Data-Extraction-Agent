// Enum 71000 - Document Direction (Sales/Purchase)
enum 71000 "AIDE Document Direction"
{
    Caption = 'Document Direction';
    Extensible = true;

    value(0; Purchase)
    {
        Caption = 'Purchase';
    }
    value(1; Sales)
    {
        Caption = 'Sales';
    }
}

// Enum 71001 - Extraction Status
enum 71001 "AIDE Extraction Status"
{
    Caption = 'Extraction Status';
    Extensible = true;

    value(0; Pending)
    {
        Caption = 'Pending';
    }
    value(1; Extracted)
    {
        Caption = 'Extracted';
    }
    value(2; "Awaiting Confirmation")
    {
        Caption = 'Awaiting Confirmation';
    }
    value(3; Confirmed)
    {
        Caption = 'Confirmed';
    }
    value(4; Posted)
    {
        Caption = 'Posted';
    }
    value(5; Rejected)
    {
        Caption = 'Rejected';
    }
    value(6; Error)
    {
        Caption = 'Error';
    }
}

// Enum 71002 - Tax Structure
enum 71002 "AIDE Tax Structure"
{
    Caption = 'Tax Structure';
    Extensible = true;

    value(0; "CGST+SGST")
    {
        Caption = 'CGST + SGST (Intra-State)';
    }
    value(1; IGST)
    {
        Caption = 'IGST (Inter-State)';
    }
    value(2; None)
    {
        Caption = 'No Tax';
    }
}