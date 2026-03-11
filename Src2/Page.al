/// <summary>
/// Card page hosting the Extension Dependency Graph control add-in.
///
/// IMPORTANT NOTES on Control Add-in trigger wiring:
///   - There is NO "OnControlReady" trigger in BC Control Add-ins.
///   - Instead, the control add-in defines an "event OnReady()" which JS fires
///     via Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnReady", []).
///   - On this page, we wire the trigger as: trigger OnReady() — matching the
///     event name defined in the controladdin object.
///   - The "trigger" keyword on a usercontrol maps to EVENTS (JS → AL direction),
///     not to procedures (AL → JS direction).
/// </summary>
page 70100 "Ext. Dependency Graph"
{
    PageType = Card;
    Caption = 'Extension Dependency Graph';
    UsageCategory = Administration;
    ApplicationArea = All;
    Editable = false;
    LinksAllowed = false;
    ShowFilter = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            // The usercontrol hosts the DependencyGraph control add-in.
            // Triggers here correspond to the EVENTS defined in the controladdin object.
            usercontrol(GraphControl; DependencyGraph)
            {
                ApplicationArea = All;

                // ── This trigger fires when JS calls InvokeExtensibilityMethod("OnReady", []) ──
                // It is our signal that vis.js is loaded and the DOM is ready.
                // We respond by building the JSON payload and sending it to JS.
                trigger OnReady()
                begin
                    IsControlReady := true;
                    LoadGraphData();
                end;

                // ── This trigger fires when the user clicks a node in the graph ──
                // JS calls InvokeExtensibilityMethod("OnNodeSelected", [id, name, pub, ver])
                trigger OnNodeSelected(AppId: Text; AppName: Text; Publisher: Text; Version: Text)
                begin
                    // Store selected extension info for potential use by other actions
                    CurrSelectedAppId := AppId;
                    CurrSelectedAppName := AppName;
                    CurrSelectedPublisher := Publisher;
                    CurrSelectedVersion := Version;
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RefreshGraph)
            {
                ApplicationArea = All;
                Caption = 'Refresh Graph';
                ToolTip = 'Reload all extension data and redraw the dependency graph.';
                Image = Refresh;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;

                trigger OnAction()
                begin
                    if not IsControlReady then begin
                        Message('The graph control is still loading. Please wait a moment and try again.');
                        exit;
                    end;
                    LoadGraphData();
                end;
            }

            action(ExportJson)
            {
                ApplicationArea = All;
                Caption = 'Export JSON';
                ToolTip = 'Download the raw JSON dependency graph payload for debugging or analysis.';
                Image = Export;
                Promoted = true;
                PromotedCategory = Process;
                PromotedOnly = true;

                trigger OnAction()
                var
                    DepGraphMgmt: Codeunit "Dependency Graph Mgmt";
                    JsonPayload: Text;
                    TempBlob: Codeunit "Temp Blob";
                    OutStr: OutStream;
                    InStr: InStream;
                    FileName: Text;
                begin
                    DepGraphMgmt.GetDependencyGraphJson(JsonPayload);

                    if JsonPayload = '' then begin
                        Message('No data available to export.');
                        exit;
                    end;

                    TempBlob.CreateOutStream(OutStr, TextEncoding::UTF8);
                    OutStr.WriteText(JsonPayload);
                    TempBlob.CreateInStream(InStr, TextEncoding::UTF8);

                    FileName := 'DependencyGraph_' +
                        Format(Today, 0, '<Year4><Month,2><Day,2>') + '_' +
                        Format(Time, 0, '<Hours24,2><Minutes,2><Seconds,2>') + '.json';

                    DownloadFromStream(InStr, 'Export Dependency Graph JSON', '', 'JSON Files (*.json)|*.json', FileName);
                end;
            }
        }
    }

    var
        /// <summary>
        /// Cached JSON payload. Rebuilt each time LoadGraphData() is called.
        /// </summary>
        GraphJsonPayload: Text;

        /// <summary>
        /// Tracks whether the JS control add-in has fired OnReady.
        /// Prevents calling LoadGraph before the control is initialised.
        /// </summary>
        IsControlReady: Boolean;

        /// <summary>Currently selected extension details (set by OnNodeSelected).</summary>
        CurrSelectedAppId: Text;
        CurrSelectedAppName: Text;
        CurrSelectedPublisher: Text;
        CurrSelectedVersion: Text;

    /// <summary>
    /// Reads extension data via the management codeunit and sends the JSON
    /// payload to the control add-in for rendering.
    ///
    /// Uses TryFunction wrapper for error safety — if the system tables are
    /// inaccessible or any unexpected error occurs, the user sees a friendly
    /// message instead of an unhandled error dialog.
    /// </summary>
    local procedure LoadGraphData()
    var
        DepGraphMgmt: Codeunit "Dependency Graph Mgmt";
    begin
        Clear(GraphJsonPayload);

        if not TryBuildGraphJson(DepGraphMgmt, GraphJsonPayload) then begin
            Message(
                'An error occurred while reading extension data.\\' +
                'Please try again or contact your administrator.\\\\' +
                'Error details: %1',
                GetLastErrorText());
            exit;
        end;

        if GraphJsonPayload = '' then begin
            Message('No installed extensions were found. The graph will be empty.');
            exit;
        end;

        // Send the JSON payload to the JavaScript control add-in.
        // This calls the "procedure LoadGraph(Text)" defined in the controladdin,
        // which maps to window.LoadGraph(jsonPayload) in app.js.
        CurrPage.GraphControl.LoadGraph(GraphJsonPayload);
    end;

    /// <summary>
    /// TryFunction wrapper around the codeunit call.
    /// If GetDependencyGraphJson raises any error (e.g., permission denied
    /// on system tables, unexpected data), this catches it and returns false
    /// so the caller can show a user-friendly message.
    /// </summary>
    [TryFunction]
    local procedure TryBuildGraphJson(var DepGraphMgmt: Codeunit "Dependency Graph Mgmt"; var Payload: Text)
    begin
        DepGraphMgmt.GetDependencyGraphJson(Payload);
    end;
}
