// Table 71001 - AIDE Extracted Invoice Header
table 71001 "AIDE Extracted Inv. Header"
{
    Caption = 'AI Extracted Invoice Header';
    DataClassification = CustomerContent;
    LookupPageId = "AIDE Extracted Invoices";
    DrillDownPageId = "AIDE Extracted Invoices";

    fields
    {
        field(1; "Entry No."; Code[20])
        {
            Caption = 'Entry No.';
        }
        field(10; "Document Direction"; Enum "AIDE Document Direction")
        {
            Caption = 'Document Direction';
        }
        field(11; "Extraction Status"; Enum "AIDE Extraction Status")
        {
            Caption = 'Extraction Status';
        }
        // SOURCE
        field(20; "Source File Name"; Text[250])
        {
            Caption = 'Source File Name';
        }
        field(21; "Upload DateTime"; DateTime)
        {
            Caption = 'Upload Date/Time';
        }
        field(22; "Uploaded By"; Code[50])
        {
            Caption = 'Uploaded By';
        }
        // EXTRACTED HEADER FIELDS
        field(100; "Invoice Number"; Text[50])
        {
            Caption = 'Invoice Number';
        }
        field(101; "Invoice Date"; Date)
        {
            Caption = 'Invoice Date';
        }
        field(102; "Due Date"; Date)
        {
            Caption = 'Due Date';
        }
        field(103; "PO Reference"; Text[50])
        {
            Caption = 'PO Reference';
        }
        field(104; "Currency Code"; Code[10])
        {
            Caption = 'Currency';
            TableRelation = Currency;
        }
        // VENDOR / SUPPLIER
        field(110; "Vendor Name"; Text[100])
        {
            Caption = 'Vendor / Supplier Name';
        }
        field(111; "Vendor GSTIN"; Text[20])
        {
            Caption = 'Vendor GSTIN';
        }
        field(112; "Vendor Address"; Text[500])
        {
            Caption = 'Vendor Address';
        }
        // BUYER / CUSTOMER
        field(120; "Buyer Name"; Text[100])
        {
            Caption = 'Buyer / Customer Name';
        }
        field(121; "Buyer GSTIN"; Text[20])
        {
            Caption = 'Buyer GSTIN';
        }
        // E-INVOICE FIELDS (INDIA)
        field(130; "IRN"; Text[100])
        {
            Caption = 'Invoice Reference Number (IRN)';
        }
        field(131; "Ack Number"; Text[50])
        {
            Caption = 'Acknowledgement Number';
        }
        field(132; "Ack Date"; Date)
        {
            Caption = 'Acknowledgement Date';
        }
        // TOTALS
        field(200; Subtotal; Decimal)
        {
            Caption = 'Subtotal';
        }
        field(201; "Total CGST"; Decimal)
        {
            Caption = 'Total CGST';
        }
        field(202; "Total SGST"; Decimal)
        {
            Caption = 'Total SGST';
        }
        field(203; "Total IGST"; Decimal)
        {
            Caption = 'Total IGST';
        }
        field(204; "Total Cess"; Decimal)
        {
            Caption = 'Total Cess';
        }
        field(205; "Total Tax"; Decimal)
        {
            Caption = 'Total Tax';
        }
        field(206; "Round Off"; Decimal)
        {
            Caption = 'Round Off';
        }
        field(207; "Grand Total"; Decimal)
        {
            Caption = 'Grand Total';
        }
        field(208; "Amount In Words"; Text[500])
        {
            Caption = 'Amount In Words';
        }
        field(209; "Tax Structure"; Enum "AIDE Tax Structure")
        {
            Caption = 'Tax Structure';
        }
        // BANK DETAILS
        field(220; "Bank Name"; Text[100])
        {
            Caption = 'Bank Name';
        }
        field(221; "Account Number"; Text[50])
        {
            Caption = 'Account Number';
        }
        field(222; "IFSC Code"; Text[20])
        {
            Caption = 'IFSC Code';
        }
        // VALIDATION
        field(300; "Needs Review"; Boolean)
        {
            Caption = 'Needs Review';
        }
        field(301; "Review Reason"; Text[500])
        {
            Caption = 'Review Reason';
        }
        field(302; "Confidence Score %"; Decimal)
        {
            Caption = 'OCR Confidence %';
        }
        field(303; "Validation Passed"; Boolean)
        {
            Caption = 'Validation Passed';
        }
        // MATCHED BC ENTITIES
        field(400; "Matched Vendor No."; Code[20])
        {
            Caption = 'Matched Vendor No.';
            TableRelation = Vendor;
        }
        field(401; "Matched Customer No."; Code[20])
        {
            Caption = 'Matched Customer No.';
            TableRelation = Customer;
        }
        field(402; "Matched PO No."; Code[20])
        {
            Caption = 'Matched Purchase Order No.';
        }
        // POSTING RESULT
        field(500; "Created Doc. Type"; Text[30])
        {
            Caption = 'Created Document Type';
        }
        field(501; "Created Doc. No."; Code[20])
        {
            Caption = 'Created Document No.';
        }
        field(502; "Posted Doc. No."; Code[20])
        {
            Caption = 'Posted Document No.';
        }
        field(503; "Posted DateTime"; DateTime)
        {
            Caption = 'Posted Date/Time';
        }
        field(504; "Posted By"; Code[50])
        {
            Caption = 'Posted By';
        }
        // CONFIRMATION
        field(600; "Confirmed By"; Code[50])
        {
            Caption = 'Confirmed By';
        }
        field(601; "Confirmed DateTime"; DateTime)
        {
            Caption = 'Confirmed Date/Time';
        }
        field(602; "User Notes"; Text[1000])
        {
            Caption = 'User Notes';
        }
        // RAW DATA
        field(700; "Raw JSON Response"; Blob)
        {
            Caption = 'Raw JSON Response';
        }
        field(701; "Source File Content"; Blob)
        {
            Caption = 'Source File Content';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Status; "Extraction Status", "Document Direction")
        {
        }
        key(Vendor; "Vendor GSTIN")
        {
        }
    }

    trigger OnInsert()
    var
        Setup: Record "AIDE Agent Setup";
        NoSeriesMgt: Codeunit NoSeriesManagement;
    begin
        if "Entry No." = '' then begin
            Setup.GetSetup();
            Setup.TestField("Staging Doc. Nos.");
            "Entry No." := NoSeriesMgt.GetNextNo(Setup."Staging Doc. Nos.", WorkDate(), true);
        end;
        "Upload DateTime" := CurrentDateTime;
        "Uploaded By" := CopyStr(UserId, 1, MaxStrLen("Uploaded By"));
    end;

    trigger OnDelete()
    var
        Lines: Record "AIDE Extracted Inv. Line";
    begin
        Lines.SetRange("Document Entry No.", "Entry No.");
        Lines.DeleteAll(true);
    end;

    procedure GetRawJSON(): Text
    var
        InStr: InStream;
        Result: Text;
    begin
        CalcFields("Raw JSON Response");
        if not "Raw JSON Response".HasValue then
            exit('');
        "Raw JSON Response".CreateInStream(InStr, TextEncoding::UTF8);
        InStr.ReadText(Result);
        exit(Result);
    end;

    procedure SetRawJSON(JSONText: Text)
    var
        OutStr: OutStream;
    begin
        "Raw JSON Response".CreateOutStream(OutStr, TextEncoding::UTF8);
        OutStr.WriteText(JSONText);
        Modify();
    end;
}