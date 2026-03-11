// Page 71000 - AIDE Confirmation Card
page 71000 "AIDE Confirmation Card"
{
    Caption = 'AI Invoice Extraction - Review & Confirm';
    PageType = Card;
    ApplicationArea = All;
    SourceTable = "AIDE Extracted Inv. Header";
    DataCaptionExpression = Rec."Entry No." + ' - ' + Rec."Vendor Name";

    layout
    {
        area(Content)
        {
            group(DocumentInfo)
            {
                Caption = '📄 Document Information';

                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Staging document number.';
                    Editable = false;
                }
                field("Document Direction"; Rec."Document Direction")
                {
                    ApplicationArea = All;
                    ToolTip = 'Purchase or Sales.';
                    Editable = false;
                    Style = Strong;
                }
                field("Extraction Status"; Rec."Extraction Status")
                {
                    ApplicationArea = All;
                    ToolTip = 'Current status.';
                    Editable = false;
                    StyleExpr = StatusStyle;
                }
                field("Source File Name"; Rec."Source File Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Uploaded file name.';
                    Editable = false;
                }
                field("Confidence Score %"; Rec."Confidence Score %")
                {
                    ApplicationArea = All;
                    ToolTip = 'OCR confidence score.';
                    Editable = false;
                    StyleExpr = ConfidenceStyle;
                }
            }
            group(ReviewAlert)
            {
                Caption = '⚠️ Review Required';
                Visible = Rec."Needs Review";

                field("Needs Review"; Rec."Needs Review")
                {
                    ApplicationArea = All;
                    ToolTip = 'This document needs manual review.';
                    Style = Unfavorable;
                }
                field("Review Reason"; Rec."Review Reason")
                {
                    ApplicationArea = All;
                    ToolTip = 'Reason for review.';
                    MultiLine = true;
                    Style = Attention;
                }
            }
            group(InvoiceHeader)
            {
                Caption = '🧾 Invoice Details (Extracted)';

                field("Invoice Number"; Rec."Invoice Number")
                {
                    ApplicationArea = All;
                    ToolTip = 'Invoice number from the document.';
                    Importance = Promoted;
                }
                field("Invoice Date"; Rec."Invoice Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Invoice date.';
                    Importance = Promoted;
                }
                field("Due Date"; Rec."Due Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Due date.';
                }
                field("PO Reference"; Rec."PO Reference")
                {
                    ApplicationArea = All;
                    ToolTip = 'Purchase Order reference.';
                }
                field("Currency Code"; Rec."Currency Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Currency.';
                }
            }
            group(VendorInfo)
            {
                Caption = '🏢 Vendor / Supplier';

                field("Vendor Name"; Rec."Vendor Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Vendor name from invoice.';
                }
                field("Vendor GSTIN"; Rec."Vendor GSTIN")
                {
                    ApplicationArea = All;
                    ToolTip = 'Vendor GSTIN.';
                }
                field("Vendor Address"; Rec."Vendor Address")
                {
                    ApplicationArea = All;
                    ToolTip = 'Vendor address.';
                    MultiLine = true;
                }
                field("Matched Vendor No."; Rec."Matched Vendor No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Matched BC Vendor.';
                    Style = Favorable;
                    Importance = Promoted;
                }
            }
            group(BuyerInfo)
            {
                Caption = '🏪 Buyer';

                field("Buyer Name"; Rec."Buyer Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Buyer name.';
                }
                field("Buyer GSTIN"; Rec."Buyer GSTIN")
                {
                    ApplicationArea = All;
                    ToolTip = 'Buyer GSTIN.';
                }
                field("Matched Customer No."; Rec."Matched Customer No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Matched BC Customer.';
                    Style = Favorable;
                    Visible = Rec."Document Direction" = Rec."Document Direction"::Sales;
                }
            }
            group(EInvoice)
            {
                Caption = '📋 E-Invoice (India)';
                Visible = Rec.IRN <> '';

                field(IRN; Rec.IRN)
                {
                    ApplicationArea = All;
                    ToolTip = 'Invoice Reference Number.';
                }
                field("Ack Number"; Rec."Ack Number")
                {
                    ApplicationArea = All;
                    ToolTip = 'Acknowledgement Number.';
                }
                field("Ack Date"; Rec."Ack Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Acknowledgement Date.';
                }
            }
            part(Lines; "AIDE Confirmation Lines")
            {
                ApplicationArea = All;
                SubPageLink = "Document Entry No." = field("Entry No.");
                Caption = '📦 Line Items';
            }
            group(Totals)
            {
                Caption = '💰 Totals';

                field(Subtotal; Rec.Subtotal)
                {
                    ApplicationArea = All;
                    ToolTip = 'Subtotal.';
                    Importance = Promoted;
                }
                group(TaxBreakup)
                {
                    Caption = 'Tax Breakup';

                    field("Tax Structure"; Rec."Tax Structure")
                    {
                        ApplicationArea = All;
                        ToolTip = 'Tax structure.';
                    }
                    field("Total CGST"; Rec."Total CGST")
                    {
                        ApplicationArea = All;
                        ToolTip = 'Total CGST.';
                        Visible = Rec."Tax Structure" = Rec."Tax Structure"::"CGST+SGST";
                    }
                    field("Total SGST"; Rec."Total SGST")
                    {
                        ApplicationArea = All;
                        ToolTip = 'Total SGST.';
                        Visible = Rec."Tax Structure" = Rec."Tax Structure"::"CGST+SGST";
                    }
                    field("Total IGST"; Rec."Total IGST")
                    {
                        ApplicationArea = All;
                        ToolTip = 'Total IGST.';
                        Visible = Rec."Tax Structure" = Rec."Tax Structure"::IGST;
                    }
                    field("Total Cess"; Rec."Total Cess")
                    {
                        ApplicationArea = All;
                        ToolTip = 'Total Cess.';
                        Visible = Rec."Total Cess" <> 0;
                    }
                    field("Total Tax"; Rec."Total Tax")
                    {
                        ApplicationArea = All;
                        ToolTip = 'Total Tax.';
                        Style = AttentionAccent;
                    }
                }
                field("Round Off"; Rec."Round Off")
                {
                    ApplicationArea = All;
                    ToolTip = 'Rounding amount.';
                }
                field("Grand Total"; Rec."Grand Total")
                {
                    ApplicationArea = All;
                    ToolTip = 'Grand Total.';
                    Style = Strong;
                    Importance = Promoted;
                }
                field("Amount In Words"; Rec."Amount In Words")
                {
                    ApplicationArea = All;
                    ToolTip = 'Amount in words.';
                    MultiLine = true;
                }
            }
            group(BankDetails)
            {
                Caption = '🏦 Bank Details';
                Visible = Rec."Bank Name" <> '';

                field("Bank Name"; Rec."Bank Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Bank name.';
                }
                field("Account Number"; Rec."Account Number")
                {
                    ApplicationArea = All;
                    ToolTip = 'Account number.';
                }
                field("IFSC Code"; Rec."IFSC Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'IFSC Code.';
                }
            }
            group(MatchInfo)
            {
                Caption = '🔗 BC Matching';

                field("Matched PO No."; Rec."Matched PO No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Matched Purchase Order.';
                    Visible = Rec."Document Direction" = Rec."Document Direction"::Purchase;
                }
                field("Validation Passed"; Rec."Validation Passed")
                {
                    ApplicationArea = All;
                    ToolTip = 'All validations passed.';
                    StyleExpr = ValidationStyle;
                }
            }
            group(UserAction)
            {
                Caption = '📝 Your Notes';

                field("User Notes"; Rec."User Notes")
                {
                    ApplicationArea = All;
                    ToolTip = 'Add any notes before confirming.';
                    MultiLine = true;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ConfirmAndInsert)
            {
                Caption = '✅ Confirm & Insert';
                ApplicationArea = All;
                Image = Approve;
                ToolTip = 'Confirm the extracted data and create the document in Business Central.';
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                Visible = IsConfirmationMode;

                trigger OnAction()
                begin
                    if Confirm('Are you sure you want to CONFIRM this data and create the document in Business Central?', true) then
                        CurrPage.Close(); // Returns Action::LookupOK
                end;
            }
            action(RejectDocument)
            {
                Caption = '❌ Reject';
                ApplicationArea = All;
                Image = Reject;
                ToolTip = 'Reject this document.';
                Promoted = true;
                PromotedCategory = Process;
                Visible = IsConfirmationMode;

                trigger OnAction()
                begin
                    if Confirm('Are you sure you want to REJECT this document?', false) then begin
                        Rec."Extraction Status" := Rec."Extraction Status"::Rejected;
                        Rec.Modify(true);
                        CurrPage.Close(); // Returns Action::Cancel
                    end;
                end;
            }
            action(ViewRawJSON)
            {
                Caption = 'View Raw JSON';
                ApplicationArea = All;
                Image = XMLFile;
                ToolTip = 'View the raw extracted JSON data.';

                trigger OnAction()
                begin
                    Message(Rec.GetRawJSON());
                end;
            }
            action(ReExtract)
            {
                Caption = '🔄 Re-Extract';
                ApplicationArea = All;
                Image = Refresh;
                ToolTip = 'Re-run OCR and extraction on this document.';

                trigger OnAction()
                var
                    Orchestrator: Codeunit "AIDE Agent Orchestrator";
                begin
                    Orchestrator.ProcessExistingDocument(Rec);
                    CurrPage.Update(false);
                    Message('Re-extraction complete.');
                end;
            }
        }
    }

    trigger OnAfterGetCurrRecord()
    begin
        SetStyles();
    end;

    var
        IsConfirmationMode: Boolean;
        StatusStyle: Text;
        ConfidenceStyle: Text;
        ValidationStyle: Text;

    procedure SetConfirmationMode(Enable: Boolean)
    begin
        IsConfirmationMode := Enable;
    end;

    local procedure SetStyles()
    begin
        case Rec."Extraction Status" of
            Rec."Extraction Status"::Extracted, Rec."Extraction Status"::"Awaiting Confirmation":
                StatusStyle := 'Ambiguous';
            Rec."Extraction Status"::Confirmed:
                StatusStyle := 'Favorable';
            Rec."Extraction Status"::Posted:
                StatusStyle := 'Favorable';
            Rec."Extraction Status"::Rejected, Rec."Extraction Status"::Error:
                StatusStyle := 'Unfavorable';
            else
                StatusStyle := 'Standard';
        end;

        if Rec."Confidence Score %" >= 90 then
            ConfidenceStyle := 'Favorable'
        else if Rec."Confidence Score %" >= 70 then
            ConfidenceStyle := 'Ambiguous'
        else
            ConfidenceStyle := 'Unfavorable';

        if Rec."Validation Passed" then
            ValidationStyle := 'Favorable'
        else
            ValidationStyle := 'Unfavorable';
    end;
}