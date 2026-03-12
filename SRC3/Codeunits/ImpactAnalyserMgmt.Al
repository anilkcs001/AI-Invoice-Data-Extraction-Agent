/// <summary>
/// Codeunit that reads installed extensions and computes version update impact.
///
/// Uses cloud-compatible APIs:
///   - Table 2000000153 "NAV App Installed App"
///   - NavApp.GetModuleInfo() → ModuleInfo → Dependencies()
///   - ModuleDependencyInfo only exposes: .Id, .Name, .Publisher
///
/// Since ModuleDependencyInfo does NOT expose MinVersion/MaxVersion in the
/// AL runtime API, we use these practical heuristic rules:
///
///   RED (Breaking):
///     - New MAJOR version differs from current MAJOR version.
///       Major version change = assumed breaking API change.
///     - New version is LOWER than current version (downgrade).
///
///   AMBER (Warning — needs recompile):
///     - New MINOR version is higher than current minor (same major).
///       API additions possible, dependent should be recompiled.
///     - New BUILD or REVISION only changed (same major.minor).
///       Low risk but recompile recommended for safety.
///
///   GREEN (Safe):
///     - New version equals current version (no actual change).
///       This shouldn't happen due to UI validation, but handled gracefully.
///
///   GREY (Unknown):
///     - NavApp.GetModuleInfo() returned false for the dependent.
///     - Cannot determine dependency relationship.
/// </summary>
codeunit 50200 "Impact Analyzer Mgmt"
{
    Access = Internal;

    /// <summary>
    /// Builds JSON of all installed extensions for the picker dropdown.
    /// Reads "NAV App Installed App" (table 2000000153) — available in Cloud + OnPrem.
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
                ExtObj.Add('versionMajor', NavAppInstalled."Version Major");
                ExtObj.Add('versionMinor', NavAppInstalled."Version Minor");
                ExtObj.Add('versionBuild', NavAppInstalled."Version Build");
                ExtObj.Add('versionRevision', NavAppInstalled."Version Revision");
                ExtObj.Add('type', ClassifyPublisher(NavAppInstalled.Publisher, OwnPublisher));
                ExtArray.Add(ExtObj);
            until NavAppInstalled.Next() = 0;

        RootObj.Add('extensions', ExtArray);
        RootObj.WriteTo(Payload);
    end;

    /// <summary>
    /// Core procedure: computes impact of updating TargetAppId to a new version.
    ///
    /// Strategy:
    ///   1. For each installed extension, get its ModuleInfo
    ///   2. Check ModuleInfo.Dependencies() for a dependency matching TargetAppId
    ///   3. ModuleDependencyInfo only gives us .Id, .Name, .Publisher
    ///      (NO min/max version range available in AL runtime)
    ///   4. We use the TARGET extension's current installed version vs the proposed
    ///      new version to determine risk level:
    ///      - Different major = RED (breaking)
    ///      - Same major, higher minor = AMBER (recompile)
    ///      - Same major.minor, higher build/rev = AMBER (low risk recompile)
    ///      - Downgrade = RED
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
        OwnPublisher: Text;
        GreenCount: Integer;
        AmberCount: Integer;
        RedCount: Integer;
        GreyCount: Integer;
        TotalCount: Integer;
        OverallRisk: Text;
        OverallMessage: Text;
        OldVersion: Text;
        NewVersionStr: Text;
        CurMajor: Integer;
        CurMinor: Integer;
        CurBuild: Integer;
        CurRevision: Integer;
        FoundDep: Boolean;
        DepName: Text;
    begin
        OwnPublisher := GetOwnPublisher();
        TargetIdClean := CleanGuid(TargetAppId);
        NewVersionStr := FormatVersion(NewMajor, NewMinor, NewBuild, NewRevision);

        // Get the target extension's current installed version
        TargetApp.Reset();
        TargetApp.SetRange("App ID", TargetAppId);
        if TargetApp.FindFirst() then begin
            CurMajor := TargetApp."Version Major";
            CurMinor := TargetApp."Version Minor";
            CurBuild := TargetApp."Version Build";
            CurRevision := TargetApp."Version Revision";
            OldVersion := FormatVersion(CurMajor, CurMinor, CurBuild, CurRevision);

            TargetObj.Add('id', TargetIdClean);
            TargetObj.Add('name', TargetApp.Name);
            TargetObj.Add('publisher', TargetApp.Publisher);
            TargetObj.Add('oldVersion', OldVersion);
            TargetObj.Add('newVersion', NewVersionStr);
        end else begin
            // Target extension not found — should not happen but handle gracefully
            TargetObj.Add('id', TargetIdClean);
            TargetObj.Add('name', 'Unknown');
            TargetObj.Add('publisher', '');
            TargetObj.Add('oldVersion', '0.0.0.0');
            TargetObj.Add('newVersion', NewVersionStr);
            OldVersion := '0.0.0.0';
        end;

        // Initialize counters
        GreenCount := 0;
        AmberCount := 0;
        RedCount := 0;
        GreyCount := 0;
        TotalCount := 0;

        // Iterate ALL installed extensions to find dependents of our target
        NavAppInstalled.Reset();
        if NavAppInstalled.FindSet() then
            repeat
                // Skip the target extension itself — it can't depend on itself
                if NavAppInstalled."App ID" <> TargetAppId then begin

                    // Try to read this extension's module info
                    if NavApp.GetModuleInfo(NavAppInstalled."App ID", ModInfo) then begin
                        DepList := ModInfo.Dependencies();
                        FoundDep := false;

                        // Check each dependency to see if it references our target
                        foreach DepInfo in DepList do begin
                            DepIdClean := CleanGuid(DepInfo.Id);

                            if DepIdClean = TargetIdClean then begin
                                FoundDep := true;

                                // This extension depends on our target.
                                // Evaluate compatibility using version heuristics.
                                EvaluateCompatibility(
                                    CurMajor, CurMinor, CurBuild, CurRevision,
                                    NewMajor, NewMinor, NewBuild, NewRevision,
                                    NavAppInstalled.Name,
                                    NewVersionStr,
                                    OldVersion,
                                    Status, StatusLabel, Reason, Action);

                                // Build dependent result object
                                Clear(DepObj);
                                DepObj.Add('id', CleanGuid(NavAppInstalled."App ID"));
                                DepObj.Add('name', NavAppInstalled.Name);
                                DepObj.Add('publisher', NavAppInstalled.Publisher);
                                DepObj.Add('version', FormatVersion(
                                    NavAppInstalled."Version Major",
                                    NavAppInstalled."Version Minor",
                                    NavAppInstalled."Version Build",
                                    NavAppInstalled."Version Revision"));
                                DepObj.Add('type', ClassifyPublisher(
                                    NavAppInstalled.Publisher, OwnPublisher));
                                DepObj.Add('status', Status);
                                DepObj.Add('statusLabel', StatusLabel);
                                // Since we cannot read min/max from ModuleDependencyInfo,
                                // we show the current installed version of the target as reference
                                DepObj.Add('minVersion', OldVersion);
                                DepObj.Add('maxVersion', '');
                                DepObj.Add('reason', Reason);
                                DepObj.Add('action', Action);
                                DepsArray.Add(DepObj);

                                // Increment status counter
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

                    end else begin
                        // GetModuleInfo failed — we cannot determine if this extension
                        // depends on our target. We skip it silently.
                        // Only extensions where we KNOW there's a dependency get reported.
                    end;
                end;
            until NavAppInstalled.Next() = 0;

        // Determine overall risk level from worst status found
        if TotalCount = 0 then begin
            OverallRisk := 'none';
            OverallMessage := 'No installed extensions depend on this one. Safe to publish any version.';
        end else if RedCount > 0 then begin
            OverallRisk := 'high';
            OverallMessage := StrSubstNo(
                '%1 extension(s) will likely break if you publish version %2.',
                RedCount, NewVersionStr);
        end else if AmberCount > 0 then begin
            OverallRisk := 'medium';
            OverallMessage := StrSubstNo(
                '%1 extension(s) should be recompiled and retested against version %2.',
                AmberCount, NewVersionStr);
        end else begin
            OverallRisk := 'low';
            OverallMessage := StrSubstNo(
                'All %1 dependent extension(s) should remain compatible with version %2.',
                GreenCount, NewVersionStr);
        end;

        // Build summary
        SummaryObj.Add('green', GreenCount);
        SummaryObj.Add('amber', AmberCount);
        SummaryObj.Add('red', RedCount);
        SummaryObj.Add('grey', GreyCount);
        SummaryObj.Add('total', TotalCount);

        // Assemble final JSON
        RootObj.Add('targetApp', TargetObj);
        RootObj.Add('overallRisk', OverallRisk);
        RootObj.Add('overallMessage', OverallMessage);
        RootObj.Add('summary', SummaryObj);
        RootObj.Add('dependents', DepsArray);
        RootObj.WriteTo(Payload);
    end;

    /// <summary>
    /// Evaluates compatibility between the current installed version of the target
    /// and the proposed new version, from the perspective of a dependent extension.
    ///
    /// Since ModuleDependencyInfo does NOT expose version range fields in the AL
    /// runtime API, we use these practical heuristic rules:
    ///
    /// RED (Breaking):
    ///   - New MAJOR differs from current MAJOR
    ///     Rationale: Major version bump conventionally signals breaking API changes.
    ///     Dependent extensions compiled against major=3 will likely fail on major=4.
    ///   - New version is LOWER than current version (downgrade)
    ///     Rationale: Dependent may use APIs added in the current version.
    ///
    /// AMBER (Warning — recompile recommended):
    ///   - Same major, but MINOR increased
    ///     Rationale: Minor version may add new APIs but should not break existing ones.
    ///     Recompilation ensures the dependent picks up any symbol changes.
    ///   - Same major.minor, but BUILD or REVISION increased
    ///     Rationale: Typically bug fixes. Very low risk but recompile for safety.
    ///
    /// GREEN (Safe):
    ///   - Versions are identical (edge case — UI should prevent this)
    /// </summary>
    local procedure EvaluateCompatibility(
        CurMaj: Integer; CurMin: Integer; CurBld: Integer; CurRev: Integer;
        NewMaj: Integer; NewMin: Integer; NewBld: Integer; NewRev: Integer;
        DependentName: Text;
        NewVersionStr: Text;
        OldVersionStr: Text;
        var Status: Text;
        var StatusLabel: Text;
        var Reason: Text;
        var Action: Text)
    var
        VersionComparison: Integer;
    begin
        // Compare new version against current version
        VersionComparison := CompareVersions(
            NewMaj, NewMin, NewBld, NewRev,
            CurMaj, CurMin, CurBld, CurRev);

        // Case 1: Downgrade — new version is LOWER than current
        if VersionComparison < 0 then begin
            Status := 'red';
            StatusLabel := 'BREAKING';
            Reason := StrSubstNo(
                'Version %1 is a downgrade from the currently installed %2. ' +
                '%3 may depend on APIs or fixes introduced in %2 that would be missing.',
                NewVersionStr, OldVersionStr, DependentName);
            Action := StrSubstNo(
                'Do not downgrade. If you must revert, recompile and test %1 against v%2 first.',
                DependentName, NewVersionStr);
            exit;
        end;

        // Case 2: Same version — no actual change
        if VersionComparison = 0 then begin
            Status := 'green';
            StatusLabel := 'SAFE';
            Reason := 'The new version is identical to the currently installed version. No impact.';
            Action := 'No action needed.';
            exit;
        end;

        // New version is HIGHER than current. Check what changed.

        // Case 3: MAJOR version changed → RED (breaking)
        if NewMaj <> CurMaj then begin
            Status := 'red';
            StatusLabel := 'BREAKING';
            Reason := StrSubstNo(
                'Major version changes from %1 to %2. By convention, major version bumps ' +
                'indicate breaking API changes. %3 was compiled against major version %1 ' +
                'and will likely fail on major version %2.',
                CurMaj, NewMaj, DependentName);
            Action := StrSubstNo(
                'Before publishing v%1: update %2 to be compatible with major version %3, ' +
                'recompile it, and test thoroughly.',
                NewVersionStr, DependentName, NewMaj);
            exit;
        end;

        // Same major version from here on

        // Case 4: MINOR version increased → AMBER (recompile)
        if NewMin > CurMin then begin
            Status := 'amber';
            StatusLabel := 'WARNING';
            Reason := StrSubstNo(
                'Minor version increases from %1.%2 to %3.%4. Minor updates may add new APIs ' +
                'or modify behavior. %5 should be recompiled to ensure symbol compatibility.',
                CurMaj, CurMin, NewMaj, NewMin, DependentName);
            Action := StrSubstNo(
                'Recompile %1 against v%2 and run regression tests before publishing.',
                DependentName, NewVersionStr);
            exit;
        end;

        // Case 5: Same major.minor, BUILD or REVISION changed → AMBER (low risk)
        if (NewBld > CurBld) or ((NewBld = CurBld) and (NewRev > CurRev)) then begin
            Status := 'amber';
            StatusLabel := 'WARNING';
            Reason := StrSubstNo(
                'Build/revision changes from %1 to %2. These are typically bug fixes with low ' +
                'risk of breaking changes. However, %3 should still be recompiled for safety.',
                OldVersionStr, NewVersionStr, DependentName);
            Action := StrSubstNo(
                'Recompile %1 against v%2 as a precaution. Risk is low.',
                DependentName, NewVersionStr);
            exit;
        end;

        // Fallback: same major.minor but minor decreased (e.g., 3.5 → 3.3 but major same)
        // This is a partial downgrade within the same major
        if NewMin < CurMin then begin
            Status := 'red';
            StatusLabel := 'BREAKING';
            Reason := StrSubstNo(
                'Minor version decreases from %1.%2 to %3.%4 within the same major version. ' +
                '%5 may use APIs added in minor version %2 that would be missing in %4.',
                CurMaj, CurMin, NewMaj, NewMin, DependentName);
            Action := StrSubstNo(
                'Do not downgrade the minor version. Recompile and test %1 if you must.',
                DependentName);
            exit;
        end;

        // Fallback for any edge case not caught above
        Status := 'amber';
        StatusLabel := 'WARNING';
        Reason := StrSubstNo(
            'Version changes from %1 to %2. Impact could not be precisely determined for %3.',
            OldVersionStr, NewVersionStr, DependentName);
        Action := StrSubstNo(
            'Recompile and test %1 against v%2 before publishing.',
            DependentName, NewVersionStr);
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

        if PubLower.Contains('microsoft') then
            exit('ms');
        if (OwnLower <> '') and (PubLower = OwnLower) then
            exit('custom');
        if IsKnownISV(PubLower) then
            exit('isv');
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
    /// Returns: -1 if A is less than B, 0 if equal, 1 if A is greater than B.
    /// Compares Major first, then Minor, then Build, then Revision.
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
    /// Strips braces and lowercases a Guid for consistent string comparison.
    /// Format specifier 4 produces {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}.
    /// </summary>
    procedure CleanGuid(GuidValue: Guid): Text
    var
        GuidText: Text;
    begin
        GuidText := LowerCase(Format(GuidValue, 0, 4));
        GuidText := DelChr(GuidText, '=', '{}');
        exit(GuidText);
    end;

    /// <summary>
    /// Returns the publisher of THIS extension.
    /// Used as baseline for classifying "custom" extensions.
    /// </summary>
    local procedure GetOwnPublisher(): Text
    var
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        exit(AppInfo.Publisher);
    end;

    /// <summary>
    /// Checks if a lowercased publisher name matches a known ISV.
    /// </summary>
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
