// Codeunit 71003 - AIDE Document Creator
codeunit 71003 "AIDE Document Creator"
{
    Caption = 'AI Invoice Document Creator';
    Access = Internal;

    procedure CreateDocument(var Header: Record "AIDE Extracted Inv. Header"): Code[20]
    begin
        case Header."Document Direction" of
            Header."Document Direction"::Purchase:
                exit(CreatePurchaseInvoice(Header));
            Header."Document Direction"::Sales:
                exit(CreateSalesInvoice(Header));
        end;
    end;

    procedure PostDocument(var Header: Record "AIDE Extracted Inv. Header"): Code[20]
    var
        PurchHeader: Record "Purchase Header";
        SalesHeader: Record "Sales Header";
        PurchPost: Codeunit "Purch.-Post";
        SalesPost: Codeunit "Sales-Post";
        PurchInvHeader: Record "Purch. Inv. Header";
        SalesInvHeader: Record "Sales Invoice Header";
        PostedNo: Code[20];
    begin
        case Header."Document Direction" of
            Header."Document Direction"::Purchase:
                begin
                    if Header."Created Doc. No." = '' then
                        CreatePurchaseInvoice(Header);

                    PurchHeader.Get(PurchHeader."Document Type"::Invoice, Header."Created Doc. No.");
                    PurchHeader.Validate(Invoice, true);
                    PurchHeader.Modify(true);
                    Commit();

                    PurchPost.Run(PurchHeader);

                    PurchInvHeader.SetRange("Pre-Assigned No.", Header."Created Doc. No.");
                    if PurchInvHeader.FindFirst() then
                        PostedNo := PurchInvHeader."No.";
                end;
            Header."Document Direction"::Sales:
                begin
                    if Header."Created Doc. No." = '' then
                        CreateSalesInvoice(Header);

                    SalesHeader.Get(SalesHeader."Document Type"::Invoice, Header."Created Doc. No.");
                    SalesHeader.Validate(Invoice, true);
                    SalesHeader.Modify(true);
                    Commit();

                    SalesPost.Run(SalesHeader);

                    SalesInvHeader.SetRange("Pre-Assigned No.", Header."Created Doc. No.");
                    if SalesInvHeader.FindFirst() then
                        PostedNo := SalesInvHeader."No.";
                end;
        end;

        Header."Posted Doc. No." := PostedNo;
        Header."Posted DateTime" := CurrentDateTime;
        Header."Posted By" := CopyStr(UserId, 1, MaxStrLen(Header."Posted By"));
        Header."Extraction Status" := Header."Extraction Status"::Posted;
        Header.Modify(true);

        exit(PostedNo);
    end;

    local procedure CreatePurchaseInvoice(var Header: Record "AIDE Extracted Inv. Header"): Code[20]
    var
        PurchHeader: Record "Purchase Header";
        PurchLine: Record "Purchase Line";
        ExtLine: Record "AIDE Extracted Inv. Line";
        LineNo: Integer;
    begin
        Header.TestField("Matched Vendor No.");
        Header.TestField("Invoice Number");
        Header.TestField("Invoice Date");

        // Create Header
        PurchHeader.Init();
        PurchHeader."Document Type" := PurchHeader."Document Type"::Invoice;
        PurchHeader."No." := '';
        PurchHeader.Insert(true);

        PurchHeader.Validate("Buy-from Vendor No.", Header."Matched Vendor No.");
        PurchHeader.Validate("Vendor Invoice No.",
            CopyStr(Header."Invoice Number", 1, MaxStrLen(PurchHeader."Vendor Invoice No.")));
        PurchHeader.Validate("Posting Date", Header."Invoice Date");
        PurchHeader.Validate("Document Date", Header."Invoice Date");

        if Header."Due Date" <> 0D then
            PurchHeader.Validate("Due Date", Header."Due Date");

        if Header."Currency Code" <> '' then
            PurchHeader.Validate("Currency Code", Header."Currency Code");

        PurchHeader.Modify(true);

        // Create Lines
        ExtLine.SetRange("Document Entry No.", Header."Entry No.");
        if ExtLine.FindSet() then begin
            LineNo := 10000;
            repeat
                PurchLine.Init();
                PurchLine."Document Type" := PurchHeader."Document Type";
                PurchLine."Document No." := PurchHeader."No.";
                PurchLine."Line No." := LineNo;
                PurchLine.Insert(true);

                if (ExtLine."Matched Type".AsInteger() > 0) and (ExtLine."Matched No." <> '') then begin
                    PurchLine.Validate(Type, ExtLine."Matched Type");
                    PurchLine.Validate("No.", ExtLine."Matched No.");
                end else begin
                    PurchLine.Validate(Type, PurchLine.Type::"G/L Account");
                    PurchLine.Validate(Description,
                        CopyStr(ExtLine.Description, 1, MaxStrLen(PurchLine.Description)));
                end;

                if ExtLine.Quantity <> 0 then
                    PurchLine.Validate(Quantity, ExtLine.Quantity)
                else
                    PurchLine.Validate(Quantity, 1);

                PurchLine.Validate("Direct Unit Cost", ExtLine."Unit Price");

                if ExtLine."Matched UOM Code" <> '' then
                    PurchLine.Validate("Unit of Measure Code", ExtLine."Matched UOM Code");

                PurchLine.Modify(true);
                LineNo += 10000;
            until ExtLine.Next() = 0;
        end;

        Header."Created Doc. Type" := 'Purchase Invoice';
        Header."Created Doc. No." := PurchHeader."No.";
        Header.Modify(true);

        exit(PurchHeader."No.");
    end;

    local procedure CreateSalesInvoice(var Header: Record "AIDE Extracted Inv. Header"): Code[20]
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        ExtLine: Record "AIDE Extracted Inv. Line";
        LineNo: Integer;
    begin
        Header.TestField("Matched Customer No.");
        Header.TestField("Invoice Number");
        Header.TestField("Invoice Date");

        // Create Header
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Invoice;
        SalesHeader."No." := '';
        SalesHeader.Insert(true);

        SalesHeader.Validate("Sell-to Customer No.", Header."Matched Customer No.");
        SalesHeader.Validate("External Document No.",
            CopyStr(Header."Invoice Number", 1, MaxStrLen(SalesHeader."External Document No.")));
        SalesHeader.Validate("Posting Date", Header."Invoice Date");
        SalesHeader.Validate("Document Date", Header."Invoice Date");

        if Header."Due Date" <> 0D then
            SalesHeader.Validate("Due Date", Header."Due Date");

        if Header."Currency Code" <> '' then
            SalesHeader.Validate("Currency Code", Header."Currency Code");

        SalesHeader.Modify(true);

        // Create Lines
        ExtLine.SetRange("Document Entry No.", Header."Entry No.");
        if ExtLine.FindSet() then begin
            LineNo := 10000;
            repeat
                SalesLine.Init();
                SalesLine."Document Type" := SalesHeader."Document Type";
                SalesLine."Document No." := SalesHeader."No.";
                SalesLine."Line No." := LineNo;
                SalesLine.Insert(true);

                if (ExtLine."Matched No." <> '') then begin
                    SalesLine.Validate(Type, SalesLine.Type::Item);
                    SalesLine.Validate("No.", ExtLine."Matched No.");
                end else begin
                    SalesLine.Validate(Type, SalesLine.Type::"G/L Account");
                    SalesLine.Validate(Description,
                        CopyStr(ExtLine.Description, 1, MaxStrLen(SalesLine.Description)));
                end;

                if ExtLine.Quantity <> 0 then
                    SalesLine.Validate(Quantity, ExtLine.Quantity)
                else
                    SalesLine.Validate(Quantity, 1);

                SalesLine.Validate("Unit Price", ExtLine."Unit Price");

                if ExtLine."Matched UOM Code" <> '' then
                    SalesLine.Validate("Unit of Measure Code", ExtLine."Matched UOM Code");

                SalesLine.Modify(true);
                LineNo += 10000;
            until ExtLine.Next() = 0;
        end;

        Header."Created Doc. Type" := 'Sales Invoice';
        Header."Created Doc. No." := SalesHeader."No.";
        Header.Modify(true);

        exit(SalesHeader."No.");
    end;
}