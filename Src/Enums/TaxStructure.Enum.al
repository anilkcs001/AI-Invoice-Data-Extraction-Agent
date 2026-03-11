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