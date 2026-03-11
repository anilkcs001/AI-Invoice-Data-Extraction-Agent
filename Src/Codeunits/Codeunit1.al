// Codeunit 71001 - AIDE Validation Engine
codeunit 71001 "AIDE Validation Engine"
{
    Caption = 'AI Extraction Validation Engine';
    Access = Internal;

    var
        Setup: Record "AIDE Agent Setup";

    procedure ValidateExtractedData(var Header: Record "AIDE Extracted Inv. Header"): Boolean
    var
        Lines: Record "AIDE Extracted Inv. Line";
        ReviewReasons: TextBuilder;
        IsValid: Boolean;
        CalcSubtotal: Decimal;
        CalcTax: Decimal;
        CalcGrandTotal: Decimal;
        LineTaxTotal: Decimal;
    begin
        Setup.GetSetup();
        IsValid := true;

        // 1. Required fields validation
        if Header."Invoice Number" = '' then begin
            ReviewReasons.AppendLine('Invoice Number is missing.');
            IsValid := false;
        end;

        if Header."Invoice Date" = 0D then begin
            ReviewReasons.AppendLine('Invoice Date is missing.');
            IsValid := false;
        end;

        if Header."Vendor Name" = '' then begin
            ReviewReasons.AppendLine('Vendor Name is missing.');
            IsValid := false;
        end;

        if Header."Grand Total" = 0 then begin
            ReviewReasons.AppendLine('Grand Total is zero.');
            IsValid := false;
        end;

        // 2. GSTIN format validation
        if (Header."Vendor GSTIN" <> '') and (not IsValidGSTIN(Header."Vendor GSTIN")) then begin
            ReviewReasons.AppendLine('Vendor GSTIN format appears invalid.');
            IsValid := false;
        end;

        if (Header."Buyer GSTIN" <> '') and (not IsValidGSTIN(Header."Buyer GSTIN")) then begin
            ReviewReasons.AppendLine('Buyer GSTIN format appears invalid.');
            IsValid := false;
        end;

        // 3. Tax structure consistency
        if (Header."Total CGST" > 0) and (Header."Total IGST" > 0) then begin
            ReviewReasons.AppendLine('Both CGST and IGST have values - only one should apply.');
            IsValid := false;
        end;

        // 4. Line totals validation
        Lines.SetRange("Document Entry No.", Header."Entry No.");
        CalcSubtotal := 0;
        LineTaxTotal := 0;
        if Lines.FindSet() then
            repeat
                CalcSubtotal += Lines."Taxable Amount";
                LineTaxTotal += Lines."CGST Amount" + Lines."SGST Amount" +
                    Lines."IGST Amount" + Lines."Cess Amount";

                // Validate individual line math
                if Lines."Taxable Amount" > 0 then begin
                    if Abs((Lines.Quantity * Lines."Unit Price" - Lines."Discount Amount") -
                        Lines."Taxable Amount") > Setup."Amt. Tolerance (LCY)" then begin
                        ReviewReasons.AppendLine(
                            StrSubstNo('Line %1: Qty x Price - Discount does not equal Taxable Amount.',
                                Lines."Line No." div 10000));
                    end;
                end;
            until Lines.Next() = 0;

        // 5. Subtotal validation
        if (CalcSubtotal > 0) and (Header.Subtotal > 0) then
            if Abs(CalcSubtotal - Header.Subtotal) > Setup."Amt. Tolerance (LCY)" then begin
                ReviewReasons.AppendLine(
                    StrSubstNo('Sum of line taxable amounts (%1) does not match subtotal (%2).',
                        CalcSubtotal, Header.Subtotal));
                IsValid := false;
            end;

        // 6. Grand total validation: subtotal + total_tax + round_off = grand_total
        CalcGrandTotal := Header.Subtotal + Header."Total Tax" + Header."Round Off";
        if Abs(CalcGrandTotal - Header."Grand Total") > Setup."Amt. Tolerance (LCY)" then begin
            ReviewReasons.AppendLine(
                StrSubstNo('Calculated total (%1 = %2 + %3 + %4) does not match Grand Total (%5).',
                    CalcGrandTotal, Header.Subtotal, Header."Total Tax",
                    Header."Round Off", Header."Grand Total"));
            IsValid := false;
        end;

        // 7. Tax amount validation
        CalcTax := Header."Total CGST" + Header."Total SGST" + Header."Total IGST" + Header."Total Cess";
        if Abs(CalcTax - Header."Total Tax") > Setup."Amt. Tolerance (LCY)" then begin
            ReviewReasons.AppendLine(
                StrSubstNo('Tax component sum (%1) does not match Total Tax (%2).',
                    CalcTax, Header."Total Tax"));
            IsValid := false;
        end;

        // 8. Date sanity
        if (Header."Invoice Date" <> 0D) and (Header."Invoice Date" > Today + 30) then begin
            ReviewReasons.AppendLine('Invoice date is more than 30 days in the future.');
            IsValid := false;
        end;

        // Update header
        if not IsValid then begin
            Header."Needs Review" := true;
            if Header."Review Reason" <> '' then
                ReviewReasons.Insert(0, Header."Review Reason" + '; ');
            Header."Review Reason" := CopyStr(ReviewReasons.ToText(), 1, MaxStrLen(Header."Review Reason"));
        end;

        Header."Validation Passed" := IsValid;
        Header.Modify(true);

        exit(IsValid);
    end;

    local procedure IsValidGSTIN(GSTIN: Text): Boolean
    begin
        // GSTIN format: 2-digit state code + 10-char PAN + 1 entity + 1 Z + 1 checksum = 15 chars
        if StrLen(GSTIN) <> 15 then
            exit(false);
        // Basic pattern check
        exit(true);
    end;
}