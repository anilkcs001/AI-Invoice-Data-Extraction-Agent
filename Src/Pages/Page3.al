// Page 71002 - AIDE Extracted Invoices List
page 71002 "AIDE Extracted Invoices"
{
    Caption = 'AI Extracted Invoices';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "AIDE Extracted Inv. Header";
    CardPageId = "AIDE Confirmation Card";
    Editable = false;
    RefreshOnActivate = true;

    layout
    {
        area(Content)
        {
            repeater(Documents)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Entry number.';
                }
                field("Document Direction"; Rec."Document Direction")
                {
                    ApplicationArea = All;
                    ToolTip = 'Purchase or Sales.';
                }
                field("Extraction Status"; Rec."Extraction Status")
                {
                    ApplicationArea = All;
                    ToolTip = 'Status.';
                    StyleExpr = StatusStyle;
                }
                field("Source File Name"; Rec."Source File Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'File name.';
                }
                field("Invoice Number"; Rec."Invoice Number")
                {
                    ApplicationArea = All;
                    ToolTip = 'Invoice number.';
                }
                field("Invoice Date"; Rec."Invoice Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Invoice date.';
                }
                field("Vendor Name"; Rec."Vendor Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Vendor name.';
                }
                field("Vendor GSTIN"; Rec."Vendor GSTIN")
                {
                    ApplicationArea = All;
                    ToolTip = 'Vendor GSTIN.';
                }
                field("Grand Total"; Rec."Grand Total")
                {
                    ApplicationArea = All;
                    ToolTip = 'Grand total.';
                }
                field("Matched Vendor No."; Rec."Matched Vendor No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Matched vendor.';
                }
                field("Needs Review"; Rec."Needs Review")
                {
                    ApplicationArea = All;
                    ToolTip = 'Needs review.';
                }
                field("Validation Passed"; Rec."Validation Passed")
                {
                    ApplicationArea = All;
                    ToolTip = 'Validation passed.';
                }
                field("Posted Doc. No."; Rec."Posted Doc. No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Posted document.';
                }
                field("Upload DateTime"; Rec."Upload DateTime")
                {
                    ApplicationArea = All;
                    ToolTip = 'Upload time.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(NewExtraction)
            {
                Caption = '🚀 New Invoice Extraction';
                ApplicationArea = All;
                Image = NewDocument;
                ToolTip = 'Upload and extract a new invoice.';
                Promoted = true;
                PromotedCategory = New;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    Orchestrator: Codeunit "AIDE Agent Orchestrator";
                begin
                    Orchestrator.RunFullAgentWorkflow();
                    CurrPage.Update(false);
                end;
            }
            action(ProcessSelected)
            {
                Caption = 'Process Selected';
                ApplicationArea = All;
                Image = Process;
                ToolTip = 'Process selected document.';
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    Orchestrator: Codeunit "AIDE Agent Orchestrator";
                begin
                    Orchestrator.ProcessExistingDocument(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(ConfirmSelected)
            {
                Caption = '✅ Confirm & Insert';
                ApplicationArea = All;
                Image = Approve;
                ToolTip = 'Confirm and insert into BC.';
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec."Extraction Status" = Rec."Extraction Status"::"Awaiting Confirmation";

                trigger OnAction()
                var
                    DocCreator: Codeunit "AIDE Document Creator";
                begin
                    if not Confirm('Confirm and create document?', true) then
                        exit;

                    Rec."Extraction Status" := Rec."Extraction Status"::Confirmed;
                    Rec."Confirmed By" := CopyStr(UserId, 1, MaxStrLen(Rec."Confirmed By"));
                    Rec."Confirmed DateTime" := CurrentDateTime;
                    Rec.Modify(true);

                    DocCreator.CreateDocument(Rec);
                    CurrPage.Update(false);
                    Message('Document %1 created: %2', Rec."Created Doc. Type", Rec."Created Doc. No.");
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        case Rec."Extraction Status" of
            Rec."Extraction Status"::Posted:
                StatusStyle := 'Favorable';
            Rec."Extraction Status"::Rejected, Rec."Extraction Status"::Error:
                StatusStyle := 'Unfavorable';
            Rec."Extraction Status"::"Awaiting Confirmation":
                StatusStyle := 'Ambiguous';
            Rec."Extraction Status"::Confirmed:
                StatusStyle := 'Favorable';
            else
                StatusStyle := 'Standard';
        end;
    end;

    var
        StatusStyle: Text;
}