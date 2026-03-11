// Page 71001 - AIDE Confirmation Lines Subpage
page 71001 "AIDE Confirmation Lines"
{
    Caption = 'Extracted Line Items';
    PageType = ListPart;
    ApplicationArea = All;
    SourceTable = "AIDE Extracted Inv. Line";

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Line No."; Rec."Line No." div 10000)
                {
                    ApplicationArea = All;
                    Caption = '#';
                    ToolTip = 'Line number.';
                    Editable = false;
                    Width = 3;
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                    ToolTip = 'Item description.';
                }
                field("HSN/SAC Code"; Rec."HSN/SAC Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'HSN/SAC code.';
                }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                    ToolTip = 'Quantity.';
                }
                field("Unit of Measure"; Rec."Unit of Measure")
                {
                    ApplicationArea = All;
                    ToolTip = 'Unit.';
                }
                field("Unit Price"; Rec."Unit Price")
                {
                    ApplicationArea = All;
                    ToolTip = 'Unit price.';
                }
                field("Discount Amount"; Rec."Discount Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Discount.';
                }
                field("Taxable Amount"; Rec."Taxable Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Taxable amount.';
                }
                field("CGST Rate %"; Rec."CGST Rate %")
                {
                    ApplicationArea = All;
                    ToolTip = 'CGST Rate.';
                    Visible = ShowCGSTSGST;
                }
                field("CGST Amount"; Rec."CGST Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'CGST Amount.';
                    Visible = ShowCGSTSGST;
                }
                field("SGST Rate %"; Rec."SGST Rate %")
                {
                    ApplicationArea = All;
                    ToolTip = 'SGST Rate.';
                    Visible = ShowCGSTSGST;
                }
                field("SGST Amount"; Rec."SGST Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'SGST Amount.';
                    Visible = ShowCGSTSGST;
                }
                field("IGST Rate %"; Rec."IGST Rate %")
                {
                    ApplicationArea = All;
                    ToolTip = 'IGST Rate.';
                    Visible = ShowIGST;
                }
                field("IGST Amount"; Rec."IGST Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'IGST Amount.';
                    Visible = ShowIGST;
                }
                field("Line Total"; Rec."Line Total")
                {
                    ApplicationArea = All;
                    ToolTip = 'Line total.';
                    Style = Strong;
                }
                field("Matched No."; Rec."Matched No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Matched BC item/GL.';
                    StyleExpr = MatchStyle;
                }
                field("Match Confidence %"; Rec."Match Confidence %")
                {
                    ApplicationArea = All;
                    ToolTip = 'Match confidence.';
                }
                field("User Corrected"; Rec."User Corrected")
                {
                    ApplicationArea = All;
                    ToolTip = 'User has corrected this line.';
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        if Rec."Matched No." <> '' then
            MatchStyle := 'Favorable'
        else
            MatchStyle := 'Ambiguous';
    end;

    var
        ShowCGSTSGST: Boolean;
        ShowIGST: Boolean;
        MatchStyle: Text;

    trigger OnOpenPage()
    var
        Header: Record "AIDE Extracted Inv. Header";
    begin
        if Rec.GetFilter("Document Entry No.") <> '' then begin
            Header.SetRange("Entry No.", Rec.GetRangeMin("Document Entry No."));
            if Header.FindFirst() then begin
                ShowCGSTSGST := Header."Tax Structure" = Header."Tax Structure"::"CGST+SGST";
                ShowIGST := Header."Tax Structure" = Header."Tax Structure"::IGST;
            end;
        end;
    end;
}