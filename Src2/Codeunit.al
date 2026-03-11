/// <summary>
/// Codeunit that builds the dependency graph JSON payload using ONLY
/// cloud-compatible system tables and APIs.
///
/// DATA SOURCES (Cloud + OnPrem compatible):
///   - Table 2000000153 "NAV App Installed App" → all installed extensions
///   - ModuleInfo data type + NavApp module     → dependency information
///
/// IMPORTANT: Tables "Published Application" (2000000160) and
/// "NAV App Dependencies" / "Published Application Dependency" (2000000161)
/// are NOT available in BC Cloud/SaaS. This codeunit avoids them entirely.
///
/// Strategy for dependencies:
///   NavApp.GetModuleInfo(AppId, ModInfo) retrieves a ModuleInfo record.
///   ModInfo.Dependencies() returns a List of ModuleDependencyInfo.
///   Each ModuleDependencyInfo has an Id (Guid) property — the dependency App ID.
/// </summary>
codeunit 70100 "Dependency Graph Mgmt"
{
    Access = Public;

    /// <summary>
    /// Main entry point. Reads installed extensions and their dependencies,
    /// then serialises a JSON payload with "nodes" and "edges" arrays.
    ///
    /// JSON structure:
    /// {
    ///   "nodes": [
    ///     { "id": "guid", "name": "...", "publisher": "...", "version": "1.0.0.0", "type": "ms|isv|custom|ext" }
    ///   ],
    ///   "edges": [
    ///     { "from": "guid-of-app", "to": "guid-of-dependency" }
    ///   ]
    /// }
    /// </summary>
    /// <param name="Payload">Output: the JSON text.</param>
    procedure GetDependencyGraphJson(var Payload: Text)
    var
        NavAppInstalledApp: Record "NAV App Installed App";
        RootObject: JsonObject;
        NodesArray: JsonArray;
        EdgesArray: JsonArray;
        NodeObject: JsonObject;
        EdgeObject: JsonObject;
        AppIdText: Text;
        VersionText: Text;
        ExtType: Text;
        CurrentTenantPublisher: Text;
        AppIdSet: Dictionary of [Text, Boolean];
        ModInfo: ModuleInfo;
        DepList: List of [ModuleDependencyInfo];
        DepInfo: ModuleDependencyInfo;
        DepIdText: Text;
    begin
        // Get the publisher of this extension to identify "custom" extensions
        CurrentTenantPublisher := GetOwnPublisher();

        // ══════════════════════════════════════════════════════════════
        // PHASE 1: Build nodes from NAV App Installed App (Table 2000000153)
        //
        // This table is available in BOTH Cloud and OnPrem environments.
        // It contains all extensions that are currently installed.
        // ══════════════════════════════════════════════════════════════
        NavAppInstalledApp.Reset();
        if NavAppInstalledApp.FindSet() then
            repeat
                Clear(NodeObject);

                // Clean the GUID: lowercase, no braces
                AppIdText := CleanGuid(NavAppInstalledApp."App ID");

                NodeObject.Add('id', AppIdText);
                NodeObject.Add('name', NavAppInstalledApp.Name);
                NodeObject.Add('publisher', NavAppInstalledApp.Publisher);

                VersionText := FormatVersion(
                    NavAppInstalledApp."Version Major",
                    NavAppInstalledApp."Version Minor",
                    NavAppInstalledApp."Version Build",
                    NavAppInstalledApp."Version Revision");
                NodeObject.Add('version', VersionText);

                ExtType := ClassifyPublisher(NavAppInstalledApp.Publisher, CurrentTenantPublisher);
                NodeObject.Add('type', ExtType);

                NodesArray.Add(NodeObject);

                // Track known App IDs so edges only reference valid nodes
                if not AppIdSet.ContainsKey(AppIdText) then
                    AppIdSet.Add(AppIdText, true);
            until NavAppInstalledApp.Next() = 0;

        // ══════════════════════════════════════════════════════════════
        // PHASE 2: Build edges using ModuleInfo.Dependencies()
        //
        // For each installed app, we retrieve its ModuleInfo via
        // NavApp.GetModuleInfo(). The Dependencies() method returns
        // a list of ModuleDependencyInfo, each with an Id property
        // representing a dependency App ID.
        //
        // This approach is fully cloud-compatible.
        // ══════════════════════════════════════════════════════════════
        NavAppInstalledApp.Reset();
        if NavAppInstalledApp.FindSet() then
            repeat
                AppIdText := CleanGuid(NavAppInstalledApp."App ID");

                // Try to get the ModuleInfo for this app
                if NavApp.GetModuleInfo(NavAppInstalledApp."App ID", ModInfo) then begin
                    DepList := ModInfo.Dependencies();

                    foreach DepInfo in DepList do begin
                        DepIdText := CleanGuid(DepInfo.Id());

                        // Only create edge if both the source and target are known nodes
                        // (both are installed extensions)
                        if AppIdSet.ContainsKey(AppIdText) and AppIdSet.ContainsKey(DepIdText) then begin
                            Clear(EdgeObject);
                            // Direction: AppIdText (this app) DEPENDS ON DepIdText (dependency)
                            EdgeObject.Add('from', AppIdText);
                            EdgeObject.Add('to', DepIdText);
                            EdgesArray.Add(EdgeObject);
                        end;
                    end;
                end;
            until NavAppInstalledApp.Next() = 0;

        // ══════════════════════════════════════════════════════════════
        // PHASE 3: Assemble final JSON
        // ══════════════════════════════════════════════════════════════
        RootObject.Add('nodes', NodesArray);
        RootObject.Add('edges', EdgesArray);
        RootObject.WriteTo(Payload);
    end;

    /// <summary>
    /// Classifies an extension's publisher into one of four categories:
    ///   'ms'     → Publisher contains 'Microsoft'
    ///   'custom' → Publisher matches this extension's publisher (tenant-specific)
    ///   'isv'    → Publisher matches known ISV names
    ///   'ext'    → Everything else (third party / unknown)
    /// </summary>
    /// <param name="Publisher">The publisher name from the installed app record.</param>
    /// <param name="CurrentTenantPublisher">
    ///   The publisher of this extension, used as the baseline for "custom".
    /// </param>
    /// <returns>Type string: 'ms', 'isv', 'custom', or 'ext'</returns>
    procedure ClassifyPublisher(Publisher: Text; CurrentTenantPublisher: Text): Text
    var
        PubLower: Text;
        TenantPubLower: Text;
    begin
        PubLower := LowerCase(Publisher);
        TenantPubLower := LowerCase(CurrentTenantPublisher);

        // Microsoft-published extensions
        if PubLower.Contains('microsoft') then
            exit('ms');

        // Custom: same publisher as this extension (i.e., your own company's extensions)
        if (TenantPubLower <> '') and (PubLower = TenantPubLower) then
            exit('custom');

        // Known ISV publishers
        if IsKnownISV(PubLower) then
            exit('isv');

        // Everything else
        exit('ext');
    end;

    /// <summary>
    /// Formats four integer version parts into a dotted version string.
    /// Example: FormatVersion(24, 1, 0, 0) → "24.1.0.0"
    /// </summary>
    procedure FormatVersion(Major: Integer; Minor: Integer; Build: Integer; Rev: Integer): Text
    begin
        exit(Format(Major) + '.' + Format(Minor) + '.' + Format(Build) + '.' + Format(Rev));
    end;

    /// <summary>
    /// Checks whether a lowercased publisher name matches known ISV publishers.
    /// This is an extensible heuristic list. Add or remove entries as appropriate
    /// for your environment.
    /// </summary>
    local procedure IsKnownISV(PubLower: Text): Boolean
    begin
        if PubLower.Contains('continia') then
            exit(true);
        if PubLower.Contains('to-increase') then
            exit(true);
        if PubLower.Contains('insight works') then
            exit(true);
        if PubLower.Contains('binary stream') then
            exit(true);
        if PubLower.Contains('jet reports') then
            exit(true);
        if PubLower.Contains('anveo') then
            exit(true);
        if PubLower.Contains('cosmo') then
            exit(true);
        if PubLower.Contains('companial') then
            exit(true);
        if PubLower.Contains('dynaway') then
            exit(true);
        if PubLower.Contains('idyn') then
            exit(true);
        if PubLower.Contains('navax') then
            exit(true);
        if PubLower.Contains('kumavision') then
            exit(true);
        if PubLower.Contains('eos solutions') then
            exit(true);
        if PubLower.Contains('statical') then
            exit(true);
        if PubLower.Contains('bardimin') then
            exit(true);
        exit(false);
    end;

    /// <summary>
    /// Converts a Guid value to a clean lowercase string without braces.
    /// BC Guids format with braces by default; JavaScript expects clean hex.
    ///
    /// Format specifier 4 produces standard GUID format: {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
    /// We then strip the braces and lowercase the result.
    /// </summary>
    local procedure CleanGuid(GuidValue: Guid): Text
    var
        GuidText: Text;
    begin
        GuidText := LowerCase(Format(GuidValue, 0, 4));
        // Remove braces using DelChr
        GuidText := DelChr(GuidText, '=', '{}');
        exit(GuidText);
    end;

    /// <summary>
    /// Returns the publisher name of THIS extension (the one containing this codeunit).
    /// Used as the baseline for identifying "custom" extensions — any extension
    /// with the same publisher is considered a custom/tenant extension.
    /// </summary>
    local procedure GetOwnPublisher(): Text
    var
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        exit(AppInfo.Publisher);
    end;
}
