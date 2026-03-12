/// <summary>
/// Codeunit that reads installed extensions and computes version update impact.
///
/// Uses cloud-compatible APIs:
///   - Table 2000000153 "NAV App Installed App"
///   - NavApp.GetModuleInfo() → ModuleInfo → Dependencies()
///
/// Compatibility rules:
///   GREEN  — new version within declared min/max range
///   AMBER  — new version exceeds max but same major, OR no range declared
///   RED    — different major version, or below minimum
///   GREY   — metadata could not be read
/// </summary>
codeunit 50200 "Impact Analyzer Mgmt"
{
    Access = Internal;

    /// <summary>
    /// Builds JSON of all installed extensions for the picker dropdown.
    /// </summary>
    procedure GetExtensionsJson(var Payload: Text)
    var
        NavAppInstalled: Record "NAV App Installed App";
        RootObj: JsonObject;
        ExtArray: JsonArray;
        ExtObj: JsonObject;
        OwnPublisher: Text;
    begin
        OwnPublisher := GetOwnPublisher();

        NavAppInstalled.Reset();
        if NavAppInstalled.FindSet() then
            repeat
                Clear(ExtObj);
                ExtObj.Add('id', CleanGuid(NavAppInstalled."App ID"));
                ExtObj.Add('name', NavAppInstalled.Name);
                ExtObj.Add('publisher', NavAppInstalled.Publisher);
                ExtObj.Add('version', FormatVersion(
                    NavAppInstalled."Version Major",
                    NavAppInstalled."Version Minor",
                    NavAppInstalled."Version Build",
                    NavAppInstalled."Version Revision"));
                ExtObj.Add('type', ClassifyPublisher(NavAppInstalled.Publisher, OwnPublisher));
                ExtArray.Add(ExtObj);
            until NavAppInstalled.Next() = 0;

        RootObj.Add('extensions', ExtArray);
        RootObj.WriteTo(Payload);
    end;

    /// <summary>
    /// Core procedure: computes impact of updating TargetAppId to a new version.
    ///
    /// For every installed extension:
    ///   1. Get its ModuleInfo via NavApp.GetModuleInfo()
    ///   2. Check if it declares a dependency on TargetAppId
    ///   3. If yes, evaluate compatibility using the four rules
    ///   4. Build a result object with status, reason, and recommended action
    /// </summary>
    procedure ComputeImpact(
        TargetAppId: Guid;
        NewMajor: Integer;
        NewMinor: Integer;
        NewBuild: Integer;
        NewRevision: Integer;
        var Payload: Text)
    var
        NavAppInstalled: Record "NAV App Installed App";
        TargetApp: Record "NAV App Installed App";
        ModInfo: ModuleInfo;
        DepList: List of [ModuleDependencyInfo];
        DepInfo: ModuleDependencyInfo;
        RootObj: JsonObject;
        TargetObj: JsonObject;
        SummaryObj: JsonObject;
        DepsArray: JsonArray;
        DepObj: JsonObject;
        TargetIdClean: Text;
        DepIdClean: Text;
        Status: Text;
        StatusLabel: Text;
        Reason: Text;
        Action: Text;
        MinVer: Text;
        MaxVer: Text;
        OwnPublisher: Text;
        GreenCount: Integer;
        AmberCount: Integer;
        RedCount: Integer;
        GreyCount: Integer;
        TotalCount: Integer;
        OverallRisk: Text;
        OverallMessage: Text;
        OldVersion: Text;
        FoundDep: Boolean;
    begin
        OwnPublisher := GetOwnPublisher();
        TargetIdClean := CleanGuid(TargetAppId);

        // Get the target extension's current info
        TargetApp.Reset();
        TargetApp.SetRange("App ID", TargetAppId);
        if TargetApp.FindFirst() then begin
            OldVersion := FormatVersion(
                TargetApp."Version Major",
                TargetApp."Version Minor",
                TargetApp."Version Build",
                TargetApp."Version Revision");
            TargetObj.Add('id', TargetIdClean);
            TargetObj.Add('name', TargetApp.Name);
            TargetObj.Add('publisher', TargetApp.Publisher);
            TargetObj.Add('oldVersion', OldVersion);
            TargetObj.Add('newVersion', FormatVersion(NewMajor, NewMinor, NewBuild, NewRevision));
        end;

        // Iterate all installed extensions to find those that depend on the target
        GreenCount := 0;
        AmberCount := 0;
        RedCount := 0;
        GreyCount := 0;

        NavAppInstalled.Reset();
        if NavAppInstalled.FindSet() then
            repeat
                // Skip the target extension itself
                if NavAppInstalled."App ID" <> TargetAppId then begin

                    // Try to get module info for this extension
                    if NavApp.GetModuleInfo(NavAppInstalled."App ID", ModInfo) then begin
                        DepList := ModInfo.Dependencies();
                        FoundDep := false;

                        // Search its dependencies for one matching our target
                        foreach DepInfo in DepList do begin
                            DepIdClean := CleanGuid(DepInfo.Id());

                            if DepIdClean = TargetIdClean then begin
                                FoundDep := true;

                                // Extract the version range this dependent declares
                                MinVer := FormatVersion(
                                    DepInfo.MinVersion().Major(),
                                    DepInfo.MinVersion().Minor(),
                                    DepInfo.MinVersion().Build(),
                                    DepInfo.MinVersion().Revision());
                                MaxVer := FormatVersion(
                                    DepInfo.MaxVersion().Major(),
                                    DepInfo.MaxVersion().Minor(),
                                    DepInfo.MaxVersion().Build(),
                                    DepInfo.MaxVersion().Revision());

                                // Evaluate compatibility using the four rules
                                EvaluateCompatibility(
                                    NewMajor, NewMinor, NewBuild, NewRevision,
                                    DepInfo.MinVersion().Major(),
                                    DepInfo.MinVersion().Minor(),
                                    DepInfo.MinVersion().Build(),
                                    DepInfo.MinVersion().Revision(),
                                    DepInfo.MaxVersion().Major(),
                                    DepInfo.MaxVersion().Minor(),
                                    DepInfo.MaxVersion().Build(),
                                    DepInfo.MaxVersion().Revision(),
                                    NavAppInstalled.Name,
                                    FormatVersion(NewMajor, NewMinor, NewBuild, NewRevision),
                                    Status, StatusLabel, Reason, Action);

                                // Build the dependent result object
                                Clear(DepObj);
                                DepObj.Add('id', CleanGuid(NavAppInstalled."App ID"));
                                DepObj.Add('name', NavAppInstalled.Name);
                                DepObj.Add('publisher', NavAppInstalled.Publisher);
                                DepObj.Add('version', FormatVersion(
                                    NavAppInstalled."Version Major",
                                    NavAppInstalled."Version Minor",
                                    NavAppInstalled."Version Build",
                                    NavAppInstalled."Version Revision"));
                                DepObj.Add('type', ClassifyPublisher(NavAppInstalled.Publisher, OwnPublisher));
                                DepObj.Add('status', Status);
                                DepObj.Add('statusLabel', StatusLabel);
                                DepObj.Add('minVersion', MinVer);
                                DepObj.Add('maxVersion', MaxVer);
                                DepObj.Add('reason', Reason);
                                DepObj.Add('action', Action);
                                DepsArray.Add(DepObj);

                                // Count by status
                                case Status of
                                    'green':
                                        GreenCount += 1;
                                    'amber':
                                        AmberCount += 1;
                                    'red':
                                        RedCount += 1;
                                    else
                                        GreyCount += 1;
                                end;

                                TotalCount += 1;
                            end;
                        end;
                    end;
                end;
            until NavAppInstalled.Next() = 0;

        // Compute overall risk
        if TotalCount = 0 then begin
            OverallRisk := 'none';
            OverallMessage := 'No extensions depend on this one. Safe to publish any version.';
        end else if RedCount > 0 then begin
            OverallRisk := 'high';
            OverallMessage := StrSubstNo('%1 extension(s) will break if you publish this version.', RedCount);
        end else if AmberCount > 0 then begin
            OverallRisk := 'medium';
            OverallMessage := StrSubstNo('%1 extension(s) need recompilation and retesting.', AmberCount);
        end else begin
            OverallRisk := 'low';
            OverallMessage := StrSubstNo('All %1 dependent extension(s) are compatible.', GreenCount);
        end;

        // Build summary object
        SummaryObj.Add('green', GreenCount);
        SummaryObj.Add('amber', AmberCount);
        SummaryObj.Add('red', RedCount);
        SummaryObj.Add('grey', GreyCount);
        SummaryObj.Add('total', TotalCount);

        // Assemble root result
        RootObj.Add('targetApp', TargetObj);
        RootObj.Add('overallRisk', OverallRisk);
        RootObj.Add('overallMessage', OverallMessage);
        RootObj.Add('summary', SummaryObj);
        RootObj.Add('dependents', DepsArray);
        RootObj.WriteTo(Payload);
    end;

    /// <summary>
    /// Evaluates compatibility between a new version and a dependent's declared range.
    ///
    /// Rule 1 (GREEN): New version within [min, max] range
    /// Rule 2 (AMBER): Exceeds max but same major version, OR no range declared
    /// Rule 3 (RED):   Different major, or below minimum
    /// Rule 4 (GREY):  Handled by caller when GetModuleInfo fails
    /// </summary>
    local procedure EvaluateCompatibility(
        NewMaj: Integer; NewMin: Integer; NewBld: Integer; NewRev: Integer;
        MinMaj: Integer; MinMin: Integer; MinBld: Integer; MinRev: Integer;
        MaxMaj: Integer; MaxMin: Integer; MaxBld: Integer; MaxRev: Integer;
        DependentName: Text;
        NewVersionStr: Text;
        var Status: Text;
        var StatusLabel: Text;
        var Reason: Text;
        var Action: Text)
    var
        MinIsZero: Boolean;
        MaxIsZero: Boolean;
        CmpWithMin: Integer;
        CmpWithMax: Integer;
    begin
        // Check if min/max are 0.0.0.0 (no range declared)
        MinIsZero := (MinMaj = 0) and (MinMin = 0) and (MinBld = 0) and (MinRev = 0);
        MaxIsZero := (MaxMaj = 0) and (MaxMin = 0) and (MaxBld = 0) and (MaxRev = 0);

        // Special case: no version constraints at all
        if MinIsZero and MaxIsZero then begin
            Status := 'amber';
            StatusLabel := 'WARNING';
            Reason := StrSubstNo(
                '%1 declares no version range for this dependency. Compatibility cannot be verified.',
                DependentName);
            Action := StrSubstNo(
                'Recompile and test %1 against v%2 before publishing.',
                DependentName, NewVersionStr);
            exit;
        end;

        // Compare new version with declared minimum
        CmpWithMin := CompareVersions(NewMaj, NewMin, NewBld, NewRev, MinMaj, MinMin, MinBld, MinRev);

        // Compare new version with declared maximum (only if max is not 0.0.0.0)
        if not MaxIsZero then
            CmpWithMax := CompareVersions(NewMaj, NewMin, NewBld, NewRev, MaxMaj, MaxMin, MaxBld, MaxRev)
        else
            CmpWithMax := 0; // No max declared — treat as unbounded

        // RULE 3a: New version below minimum → RED
        if (not MinIsZero) and (CmpWithMin < 0) then begin
            Status := 'red';
            StatusLabel := 'BREAKING';
            Reason := StrSubstNo(
                'New version %1 is below the minimum required version %2.%3.%4.%5. This is a downgrade that will break %6.',
                NewVersionStr, MinMaj, MinMin, MinBld, MinRev, DependentName);
            Action := StrSubstNo(
                'Do not downgrade below v%1.%2.%3.%4, or update %5 to accept lower versions.',
                MinMaj, MinMin, MinBld, MinRev, DependentName);
            exit;
        end;

        // RULE 3b: Different major version → RED
        if (not MinIsZero) and (NewMaj <> MinMaj) then begin
            Status := 'red';
            StatusLabel := 'BREAKING';
            Reason := StrSubstNo(
                'New version %1 has major version %2, but %3 expects major version %4. Major version changes are breaking.',
                NewVersionStr, NewMaj, DependentName, MinMaj);
            Action := StrSubstNo(
                'Update %1 to declare compatibility with major version %2 and recompile before publishing.',
                DependentName, NewMaj);
            exit;
        end;

        // Check against max if declared
        if not MaxIsZero then begin
            // RULE 1: Within range [min, max] → GREEN
            if CmpWithMax <= 0 then begin
                Status := 'green';
                StatusLabel := 'SAFE';
                Reason := StrSubstNo(
                    'New version %1 is within the accepted range (≥%2.%3.%4.%5 and ≤%6.%7.%8.%9).',
                    NewVersionStr, MinMaj, MinMin, MinBld, MinRev, MaxMaj, MaxMin, MaxBld, MaxRev);
                Action := 'No action needed. This extension will continue to work.';
                exit;
            end;

            // RULE 2: Exceeds max but same major → AMBER
            if NewMaj = MaxMaj then begin
                Status := 'amber';
                StatusLabel := 'WARNING';
                Reason := StrSubstNo(
                    'New version %1 exceeds the maximum declared version %2.%3.%4.%5, but remains on major version %6.',
                    NewVersionStr, MaxMaj, MaxMin, MaxBld, MaxRev, NewMaj);
                Action := StrSubstNo(
                    'Recompile %1 against v%2 and update its dependency range to include the new version.',
                    DependentName, NewVersionStr);
                exit;
            end;

            // RULE 3a again: Exceeds max AND different major → RED
            Status := 'red';
            StatusLabel := 'BREAKING';
            Reason := StrSubstNo(
                'New version %1 exceeds the maximum %2.%3.%4.%5 and has a different major version (%6 vs %7). This is a breaking change.',
                NewVersionStr, MaxMaj, MaxMin, MaxBld, MaxRev, NewMaj, MaxMaj);
            Action := StrSubstNo(
                'Update %1 to declare compatibility with v%2 and recompile before publishing.',
                DependentName, NewVersionStr);
            exit;
        end;

        // Max is 0.0.0.0 (unbounded) and min is met → check major match
        if NewMaj = MinMaj then begin
            // Same major, above or at min, no max → GREEN
            Status := 'green';
            StatusLabel := 'SAFE';
            Reason := StrSubstNo(
                'New version %1 meets the minimum requirement (≥%2.%3.%4.%5) with no maximum cap.',
                NewVersionStr, MinMaj, MinMin, MinBld, MinRev);
            Action := 'No action needed. This extension will continue to work.';
        end else begin
            // Different major, no max declared → RED
            Status := 'red';
            StatusLabel := 'BREAKING';
            Reason := StrSubstNo(
                'New version %1 has major version %2, but %3 expects major version %4. Major version changes are breaking.',
                NewVersionStr, NewMaj, DependentName, MinMaj);
            Action := StrSubstNo(
                'Update %1 to declare compatibility with major version %2 and recompile.',
                DependentName, NewMaj);
        end;
    end;

    /// <summary>
    /// Classifies a publisher into ms/isv/custom/ext categories.
    /// </summary>
    procedure ClassifyPublisher(Publisher: Text; OwnPublisher: Text): Text
    var
        PubLower: Text;
        OwnLower: Text;
    begin
        PubLower := LowerCase(Publisher);
        OwnLower := LowerCase(OwnPublisher);

        if PubLower.Contains('microsoft') then exit('ms');
        if (OwnLower <> '') and (PubLower = OwnLower) then exit('custom');
        if IsKnownISV(PubLower) then exit('isv');
        exit('ext');
    end;

    /// <summary>
    /// Formats four integer version components into "Major.Minor.Build.Revision".
    /// </summary>
    procedure FormatVersion(Major: Integer; Minor: Integer; Build: Integer; Rev: Integer): Text
    begin
        exit(Format(Major) + '.' + Format(Minor) + '.' + Format(Build) + '.' + Format(Rev));
    end;

    /// <summary>
    /// Compares two version quadruples lexicographically.
    /// Returns: -1 if A &lt; B, 0 if A = B, 1 if A &gt; B
    /// </summary>
    procedure CompareVersions(
        AMaj: Integer; AMin: Integer; ABld: Integer; ARev: Integer;
        BMaj: Integer; BMin: Integer; BBld: Integer; BRev: Integer): Integer
    begin
        if AMaj < BMaj then exit(-1);
        if AMaj > BMaj then exit(1);
        if AMin < BMin then exit(-1);
        if AMin > BMin then exit(1);
        if ABld < BBld then exit(-1);
        if ABld > BBld then exit(1);
        if ARev < BRev then exit(-1);
        if ARev > BRev then exit(1);
        exit(0);
    end;

    /// <summary>
    /// Strips braces and lowercases a Guid for clean comparison.
    /// </summary>
    procedure CleanGuid(GuidValue: Guid): Text
    var
        GuidText: Text;
    begin
        GuidText := LowerCase(Format(GuidValue, 0, 4));
        GuidText := DelChr(GuidText, '=', '{}');
        exit(GuidText);
    end;

    local procedure GetOwnPublisher(): Text
    var
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        exit(AppInfo.Publisher);
    end;

    local procedure IsKnownISV(PubLower: Text): Boolean
    begin
        if PubLower.Contains('continia') then exit(true);
        if PubLower.Contains('to-increase') then exit(true);
        if PubLower.Contains('insight works') then exit(true);
        if PubLower.Contains('binary stream') then exit(true);
        if PubLower.Contains('jet reports') then exit(true);
        if PubLower.Contains('anveo') then exit(true);
        if PubLower.Contains('cosmo') then exit(true);
        if PubLower.Contains('companial') then exit(true);
        if PubLower.Contains('dynaway') then exit(true);
        if PubLower.Contains('idyn') then exit(true);
        if PubLower.Contains('navax') then exit(true);
        if PubLower.Contains('kumavision') then exit(true);
        if PubLower.Contains('eos solutions') then exit(true);
        exit(false);
    end;
}