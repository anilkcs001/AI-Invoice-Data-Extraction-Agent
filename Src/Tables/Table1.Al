// Table 71002 - AIDE Extracted Invoice Line
table 71002 "AIDE Extracted Inv. Line"
{
    Caption = 'AI Extracted Invoice Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Document Entry No."; Code[20])
        {
            Caption = 'Document Entry No.';
            TableRelation = "AIDE Extracted Inv. Header";
        }
        field(2; "Line No."; Integer)
        {
            Caption = 'Line No.';
        }
        field(10; Description; Text[250])
        {
            Caption = 'Description';
        }
        field(11; "HSN/SAC Code"; Code[10])
        {
            Caption = 'HSN/SAC Code';
        }
        field(12; Quantity; Decimal)
        {
            Caption = 'Quantity';
            DecimalPlaces = 0 : 5;
        }
        field(13; "Unit of Measure"; Text[30])
        {
            Caption = 'Unit of Measure';
        }
        field(14; "Unit Price"; Decimal)
        {
            Caption = 'Unit Price';
            DecimalPlaces = 0 : 5;
        }
        field(15; "Discount Amount"; Decimal)
        {
            Caption = 'Discount Amount';
        }
        field(16; "Taxable Amount"; Decimal)
        {
            Caption = 'Taxable Amount';
        }
        // GST Breakup
        field(20; "CGST Rate %"; Decimal)
        {
            Caption = 'CGST Rate %';
        }
        field(21; "CGST Amount"; Decimal)
        {
            Caption = 'CGST Amount';
        }
        field(22; "SGST Rate %"; Decimal)
        {
            Caption = 'SGST Rate %';
        }
        field(23; "SGST Amount"; Decimal)
        {
            Caption = 'SGST Amount';
        }
        field(24; "IGST Rate %"; Decimal)
        {
            Caption = 'IGST Rate %';
        }
        field(25; "IGST Amount"; Decimal)
        {
            Caption = 'IGST Amount';
        }
        field(26; "Cess Amount"; Decimal)
        {
            Caption = 'Cess Amount';
        }
        field(27; "Line Total"; Decimal)
        {
            Caption = 'Line Total';
        }
        // MATCHED BC FIELDS
        field(100; "Matched Type"; Enum "Purchase Line Type")
        {
            Caption = 'Matched Type';
        }
        field(101; "Matched No."; Code[20])
        {
            Caption = 'Matched Item / GL No.';
        }
        field(102; "Matched UOM Code"; Code[10])
        {
            Caption = 'Matched Unit of Measure';
            TableRelation = "Unit of Measure";
        }
        field(103; "Match Confidence %"; Decimal)
        {
            Caption = 'Match Confidence %';
        }
        field(110; "User Corrected"; Boolean)
        {
            Caption = 'User Corrected';
        }
    }

    keys
    {
        key(PK; "Document Entry No.", "Line No.")
        {
            Clustered = true;
        }
    }
}