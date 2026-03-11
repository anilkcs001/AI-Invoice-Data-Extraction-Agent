// Codeunit 71005 - AIDE Install
codeunit 71005 "AIDE Install"
{
    Subtype = Install;
    Access = Internal;

    trigger OnInstallAppPerCompany()
    var
        Setup: Record "AIDE Agent Setup";
    begin
        if not Setup.Get() then begin
            Setup.Init();
            Setup."Azure DI Model ID" := 'prebuilt-invoice';
            Setup."Confidence Threshold %" := 85;
            Setup."Auto Match Vendor" := true;
            Setup."Auto Match Customer" := true;
            Setup."Auto Match Items" := true;
            Setup."Enable GST Validation" := true;
            Setup."Amt. Tolerance (LCY)" := 1;
            Setup.Insert(true);
        end;
    end;
}