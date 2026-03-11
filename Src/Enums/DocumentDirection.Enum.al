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