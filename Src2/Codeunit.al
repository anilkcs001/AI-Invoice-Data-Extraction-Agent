/// <summary>
/// Codeunit that reads BC system tables to build a JSON payload
/// representing all published extensions and their dependency relationships.
/// </summary>
codeunit 70100 "Dependency Graph Mgmt"
{
    Access = Public;

    /// <summary>
    /// Main entry point. Reads the Published Application and Published Application Dependency
    /// system tables and returns a JSON string with two arrays: nodes and edges.
    ///
    /// JSON structure:
    /// {
    ///   "nodes": [ { "id": "guid", "name": "...", "publisher": "...", "version": "1.0.0.0", "type": "ms|isv|custom|ext" } ],
    ///   "edges": [ { "from": "guid", "to": "guid" } ]
    /// }
    /// </summary>
    /// <param name="Payload">The resulting JSON text (output parameter).</param>
    procedure GetDependencyGraphJson(var Payload: Text)
    var
        PubApp: Record "Published Application";
        PubAppDep: Record "NAV App Installed App";
        RootObject: JsonObject;
        NodesArray: JsonArray;
        EdgesArray: JsonArray;
        NodeObject: JsonObject;
        EdgeObject: JsonObject;
        AppIdText: Text;
        DepAppIdText: Text;
        VersionText: Text;
        ExtType: Text;
        CurrentTenantPublisher: Text;
        AppIdSet: Dictionary of [Text, Boolean];
    begin
        // Determine the "current tenant publisher" for classifying custom extensions.
        // We use the publisher of this very extension as a proxy; however, in many
        // environments the admin may override this. A simple heuristic: use the
        // publisher of the extension whose Codeunit this is.
        CurrentTenantPublisher := GetOwnPublisher();

        // ── Build Nodes ─────────────────────────────────────────────────
        // Read all published extensions. The system table "Published Application"
        // (2000000160) contains every extension that has been published to the server.
        PubApp.Reset();
        // Note: In some BC versions the "Package Type" field may not exist or may not
        // be filterable. We handle this by simply reading all records. Extensions of
        // type "Package" are identifiable by publisher = 'Microsoft' and specific names;
        // we include them but classify them accordingly.
        if PubApp.FindSet() then
            repeat
                Clear(NodeObject);

                AppIdText := LowerCase(Format(PubApp."Package ID", 0, 4).TrimStart('{').TrimEnd('}'));
                // Use the actual App ID field for the node identifier
                AppIdText := CleanGuid(PubApp."ID");

                NodeObject.Add('id', AppIdText);
                NodeObject.Add('name', PubApp.Name);
                NodeObject.Add('publisher', PubApp.Publisher);

                VersionText := FormatVersion(
                    PubApp."Version Major",
                    PubApp."Version Minor",
                    PubApp."Version Build",
                    PubApp."Version Revision");
                NodeObject.Add('version', VersionText);

                ExtType := ClassifyPublisher(PubApp.Publisher, CurrentTenantPublisher);
                NodeObject.Add('type', ExtType);

                NodesArray.Add(NodeObject);

                // Track which App IDs exist so we only create edges for known nodes
                if not AppIdSet.ContainsKey(AppIdText) then
                    AppIdSet.Add(AppIdText, true);
            until PubApp.Next() = 0;

        // ── Build Edges ─────────────────────────────────────────────────
        // The "NAV App Installed App" table (2000000153) or "Published Application Dependency"
        // table is used for dependency info. We use table 2000000161 as specified.
        BuildEdges(EdgesArray, AppIdSet);

        // ── Assemble root JSON ──────────────────────────────────────────
        RootObject.Add('nodes', NodesArray);
        RootObject.Add('edges', EdgesArray);
        RootObject.WriteTo(Payload);
    end;

    /// <summary>
    /// Builds the edges array by reading the NAV App Dependencies system virtual table.
    /// Table 2000000161 "NAV App Installed App" stores dependency relationships.
    /// </summary>
    local procedure BuildEdges(var EdgesArray: JsonArray; AppIdSet: Dictionary of [Text, Boolean])
    var
        AppDep: Record "NAV App Dependencies";
        EdgeObject: JsonObject;
        FromId: Text;
        ToId: Text;
    begin
        // Table "NAV App Dependencies" (2000000161) has the dependency mappings.
        // Each record represents: the app identified by "App ID" depends on "Dependency ID".
        AppDep.Reset();
        if AppDep.FindSet() then
            repeat
                FromId := CleanGuid(AppDep."App ID");
                ToId := CleanGuid(AppDep."Dependency ID");

                // Only include edges where both endpoints exist in our node set
                if AppIdSet.ContainsKey(FromId) and AppIdSet.ContainsKey(ToId) then begin
                    Clear(EdgeObject);
                    EdgeObject.Add('from', FromId);
                    EdgeObject.Add('to', ToId);
                    EdgesArray.Add(EdgeObject);
                end;
            until AppDep.Next() = 0;
    end;

    /// <summary>
    /// Classifies an extension publisher into one of four categories.
    /// </summary>
    /// <param name="Publisher">The publisher name from the Published Application record.</param>
    /// <param name="CurrentTenantPublisher">The publisher name considered "custom" for this tenant.</param>
    /// <returns>'ms', 'isv', 'custom', or 'ext'</returns>
    procedure ClassifyPublisher(Publisher: Text; CurrentTenantPublisher: Text): Text
    var
        PubLower: Text;
        TenantPubLower: Text;
    begin
        PubLower := LowerCase(Publisher);
        TenantPubLower := LowerCase(CurrentTenantPublisher);

        // Microsoft published
        if PubLower.Contains('microsoft') then
            exit('ms');

        // Custom: matches the current tenant/company publisher
        if (TenantPubLower <> '') and (PubLower = TenantPubLower) then
            exit('custom');

        // Known large ISV publishers – extend this list as needed
        if IsKnownISV(PubLower) then
            exit('isv');

        // Everything else is third party
        exit('ext');
    end;

    /// <summary>
    /// Checks if a publisher (lowercased) is a known ISV.
    /// This is a heuristic list; extend as appropriate for your environment.
    /// </summary>
    local procedure IsKnownISV(PubLower: Text): Boolean
    begin
        // Common BC ISV publishers – this is not exhaustive but covers major players
        if PubLower.Contains('continia') then exit(true);
        if PubLower.Contains('to-increase') then exit(true);
        if PubLower.Contains('insight works') then exit(true);
        if PubLower.Contains('binary stream') then exit(true);
        if PubLower.Contains('jet reports') then exit(true);
        if PubLower.Contains('anveo') then exit(true);
        if PubLower.Contains('cosmo') then exit(true);
        if PubLower.Contains('thatit') then exit(true);
        if PubLower.Contains('companial') then exit(true);
        if PubLower.Contains('dynaway') then exit(true);
        if PubLower.Contains('idyn') then exit(true);
        if PubLower.Contains('navax') then exit(true);
        if PubLower.Contains('kumavision') then exit(true);
        if PubLower.Contains('eos solutions') then exit(true);
        if PubLower.Contains('document capture') then exit(true);
        exit(false);
    end;

    /// <summary>
    /// Formats four integer version components into a single dotted string.
    /// </summary>
    procedure FormatVersion(Major: Integer; Minor: Integer; Build: Integer; Rev: Integer): Text
    begin
        exit(Format(Major) + '.' + Format(Minor) + '.' + Format(Build) + '.' + Format(Rev));
    end;

    /// <summary>
    /// Cleans a GUID field value into a lowercase string without braces.
    /// BC GUIDs are stored with braces; JS expects clean lowercase hex.
    /// </summary>
    local procedure CleanGuid(GuidValue: Guid): Text
    var
        GuidText: Text;
    begin
        GuidText := LowerCase(Format(GuidValue, 0, 4));
        GuidText := GuidText.TrimStart('{').TrimEnd('}');
        exit(GuidText);
    end;

    /// <summary>
    /// Retrieves the publisher of this extension (the one running this codeunit)
    /// so we can use it as the "current tenant publisher" for classifying custom extensions.
    /// </summary>
    local procedure GetOwnPublisher(): Text
    var
        AppInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(AppInfo);
        exit(AppInfo.Publisher);
    end;
}