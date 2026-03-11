// Codeunit 71002 - AIDE Entity Matcher
codeunit 71002 "AIDE Entity Matcher"
{
    Caption = 'AI Entity Matching Engine';
    Access = Internal;

    var
        Setup: Record "AIDE Agent Setup";

    procedure MatchEntities(var Header: Record "AIDE Extracted Inv. Header")
    begin
        Setup.GetSetup();

        case Header."Document Direction" of
            Header."Document Direction"::Purchase:
                begin
                    if Setup."Auto Match Vendor" then
                        MatchVendor(Header);
                    if Setup."Auto Match Items" then
                        MatchItemsForPurchase(Header);
                    MatchPurchaseOrder(Header);
                end;
            Header."Document Direction"::Sales:
                begin
                    if Setup."Auto Match Customer" then
                        MatchCustomer(Header);
                    if Setup."Auto Match Items" then
                        MatchItemsForSales(Header);
                end;
        end;
    end;

    local procedure MatchVendor(var Header: Record "AIDE Extracted Inv. Header")
    var
        Vendor: Record Vendor;
    begin
        // Strategy 1: GSTIN match
        if Header."Vendor GSTIN" <> '' then begin
            Vendor.SetFilter("GST Registration No.", '@' + Header."Vendor GSTIN");
            if Vendor.FindFirst() then
                if Vendor.Count = 1 then begin
                    Header."Matched Vendor No." := Vendor."No.";
                    Header.Modify(true);
                    exit;
                end;

            // Fallback: check VAT Registration No.
            Vendor.Reset();
            Vendor.SetFilter("VAT Registration No.", '@' + Header."Vendor GSTIN");
            if Vendor.FindFirst() then
                if Vendor.Count = 1 then begin
                    Header."Matched Vendor No." := Vendor."No.";
                    Header.Modify(true);
                    exit;
                end;
        end;

        // Strategy 2: Name match
        if Header."Vendor Name" <> '' then begin
            Vendor.Reset();
            Vendor.SetFilter(Name, '@*' + CopyStr(Header."Vendor Name", 1, 50) + '*');
            if Vendor.FindFirst() then
                if Vendor.Count = 1 then begin
                    Header."Matched Vendor No." := Vendor."No.";
                    Header.Modify(true);
                    exit;
                end;
        end;
    end;

    local procedure MatchCustomer(var Header: Record "AIDE Extracted Inv. Header")
    var
        Customer: Record Customer;
    begin
        // Strategy 1: GSTIN match
        if Header."Buyer GSTIN" <> '' then begin
            Customer.SetFilter("GST Registration No.", '@' + Header."Buyer GSTIN");
            if Customer.FindFirst() then
                if Customer.Count = 1 then begin
                    Header."Matched Customer No." := Customer."No.";
                    Header.Modify(true);
                    exit;
                end;
        end;

        // Strategy 2: Name match
        if Header."Buyer Name" <> '' then begin
            Customer.Reset();
            Customer.SetFilter(Name, '@*' + CopyStr(Header."Buyer Name", 1, 50) + '*');
            if Customer.FindFirst() then
                if Customer.Count = 1 then begin
                    Header."Matched Customer No." := Customer."No.";
                    Header.Modify(true);
                    exit;
                end;
        end;
    end;

    local procedure MatchItemsForPurchase(var Header: Record "AIDE Extracted Inv. Header")
    var
        Line: Record "AIDE Extracted Inv. Line";
        Item: Record Item;
    begin
        Line.SetRange("Document Entry No.", Header."Entry No.");
        if Line.FindSet() then
            repeat
                // Strategy 1: HSN/SAC code
                if Line."HSN/SAC Code" <> '' then begin
                    Item.SetFilter("HSN/SAC Code", '@' + Line."HSN/SAC Code");
                    if Item.FindFirst() then begin
                        Line."Matched Type" := Line."Matched Type"::Item;
                        Line."Matched No." := Item."No.";
                        Line."Matched UOM Code" := Item."Base Unit of Measure";
                        Line."Match Confidence %" := 80;
                        Line.Modify(true);
                    end else begin
                        Item.Reset();
                        MatchItemByDescription(Line, Item);
                    end;
                end else
                    MatchItemByDescription(Line, Item);
            until Line.Next() = 0;
    end;

    local procedure MatchItemsForSales(var Header: Record "AIDE Extracted Inv. Header")
    var
        Line: Record "AIDE Extracted Inv. Line";
        Item: Record Item;
    begin
        Line.SetRange("Document Entry No.", Header."Entry No.");
        if Line.FindSet() then
            repeat
                if Line."HSN/SAC Code" <> '' then begin
                    Item.SetFilter("HSN/SAC Code", '@' + Line."HSN/SAC Code");
                    if Item.FindFirst() then begin
                        Line."Matched Type" := Line."Matched Type"::Item;
                        Line."Matched No." := Item."No.";
                        Line."Matched UOM Code" := Item."Base Unit of Measure";
                        Line."Match Confidence %" := 80;
                        Line.Modify(true);
                    end else begin
                        Item.Reset();
                        MatchItemByDescription(Line, Item);
                    end;
                end else
                    MatchItemByDescription(Line, Item);
            until Line.Next() = 0;
    end;

    local procedure MatchItemByDescription(var Line: Record "AIDE Extracted Inv. Line"; var Item: Record Item)
    var
        SearchDesc: Text;
    begin
        if Line.Description = '' then
            exit;

        SearchDesc := CopyStr(Line.Description, 1, 50);
        Item.Reset();
        Item.SetFilter(Description, '@*' + SearchDesc + '*');
        if Item.FindFirst() then
            if Item.Count = 1 then begin
                Line."Matched Type" := Line."Matched Type"::Item;
                Line."Matched No." := Item."No.";
                Line."Matched UOM Code" := Item."Base Unit of Measure";
                Line."Match Confidence %" := 60;
                Line.Modify(true);
            end;
    end;

    local procedure MatchPurchaseOrder(var Header: Record "AIDE Extracted Inv. Header")
    var
        PurchHeader: Record "Purchase Header";
    begin
        if Header."PO Reference" = '' then
            exit;

        PurchHeader.SetRange("Document Type", PurchHeader."Document Type"::Order);
        PurchHeader.SetFilter("No.", '@' + Header."PO Reference");
        if Header."Matched Vendor No." <> '' then
            PurchHeader.SetRange("Buy-from Vendor No.", Header."Matched Vendor No.");

        if PurchHeader.FindFirst() then begin
            Header."Matched PO No." := PurchHeader."No.";
            Header.Modify(true);
        end;
    end;
}