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