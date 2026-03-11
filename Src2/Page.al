/// <summary>
/// Card page hosting the Extension Dependency Graph control add-in.
/// Provides a visual, interactive view of all published extensions and their dependencies.
/// </summary>
page 70100 "Ext. Dependency Graph"
{
    PageType = Card;
    Caption = 'Extension Dependency Graph';
    UsageCategory = Administration;
    ApplicationArea = All;
    // Prevent the standard BC banner/factboxes from cluttering the view
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
            // The control add-in fills the entire content area.
            // VerticalStretch + HorizontalStretch ensure it resizes with the page.
            usercontrol(GraphControl; DependencyGraph)
            {
                ApplicationArea = All;

                /// <summary>
                /// Fires when the JavaScript layer has finished loading vis.js
                /// and building the DOM. We then send the graph data.
                /// </summary>
                trigger OnControlReady()
                begin
                    LoadGraphData();
                end;

                /// <summary>
                /// Fires when the user clicks a node in the graph.
                /// Can be used for logging, navigation, or additional actions.
                /// </summary>
                trigger OnNodeSelected(AppId: Text; AppName: Text; Publisher: Text; Version: Text)
                begin
                    // Optional: track selected extension or perform additional actions.
                    // For now, the detail panel in JS handles the display.
                    // Example: Message('Selected: %1 by %2 (v%3)', AppName, Publisher, Version);
                    CurrSelectedAppId := AppId;
                    CurrSelectedAppName := AppName;
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Refresh)
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
                    LoadGraphData();
                end;
            }

            action(ExportJson)
            {
                ApplicationArea = All;
                Caption = 'Export JSON';
                ToolTip = 'Download the raw JSON dependency graph data for debugging.';
                Image = Export;
                Promoted = true;
                PromotedCategory = Process;
                PromotedOnly = true;

                trigger OnAction()
                var
                    DepGraphMgmt: Codeunit "Dependency Graph Mgmt";
                    JsonPayload: Text;
                    TempBlob: Codeunit "Temp Blob";
                    OutStream: OutStream;
                    InStream: InStream;
                    FileName: Text;
                begin
                    DepGraphMgmt.GetDependencyGraphJson(JsonPayload);

                    if JsonPayload = '' then begin
                        Message('No data available to export.');
                        exit;
                    end;

                    TempBlob.CreateOutStream(OutStream, TextEncoding::UTF8);
                    OutStream.WriteText(JsonPayload);
                    TempBlob.CreateInStream(InStream, TextEncoding::UTF8);
                    FileName := 'DependencyGraph_' + Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2>_<Hours24><Minutes,2>') + '.json';
                    DownloadFromStream(InStream, 'Export Dependency Graph', '', 'JSON Files (*.json)|*.json', FileName);
                end;
            }
        }
    }

    var
        /// <summary>Cached JSON payload to avoid rebuilding on repeated calls within the same session.</summary>
        GraphJsonPayload: Text;
        /// <summary>Tracks the currently selected App ID (set by OnNodeSelected callback).</summary>
        CurrSelectedAppId: Text;
        /// <summary>Tracks the currently selected App Name.</summary>
        CurrSelectedAppName: Text;

    /// <summary>
    /// Reads extension data via the management codeunit and sends it to the control add-in.
    /// Includes error handling so the user sees a friendly message if something goes wrong.
    /// </summary>
    local procedure LoadGraphData()
    var
        DepGraphMgmt: Codeunit "Dependency Graph Mgmt";
    begin
        Clear(GraphJsonPayload);

        // Build JSON from system tables. Wrap in error handling for robustness.
        if not TryBuildGraphJson(DepGraphMgmt, GraphJsonPayload) then begin
            Message('An error occurred while reading extension data.\Please try refreshing the page.\Error: %1', GetLastErrorText());
            exit;
        end;

        if GraphJsonPayload = '' then begin
            Message('No published extensions found. The graph will be empty.');
            exit;
        end;

        // Send data to the JavaScript control add-in for rendering
        CurrPage.GraphControl.LoadGraph(GraphJsonPayload);
    end;

    /// <summary>
    /// Wrapper using [TryFunction] to safely attempt JSON building.
    /// If the system tables are inaccessible or an unexpected error occurs,
    /// this returns false instead of raising an unhandled error.
    /// </summary>
    [TryFunction]
    local procedure TryBuildGraphJson(var DepGraphMgmt: Codeunit "Dependency Graph Mgmt"; var Payload: Text)
    begin
        DepGraphMgmt.GetDependencyGraphJson(Payload);
    end;
}