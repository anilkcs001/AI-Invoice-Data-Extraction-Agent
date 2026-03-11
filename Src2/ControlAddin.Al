/// <summary>
/// Control Add-in hosting an interactive vis.js dependency graph.
/// 
/// IMPORTANT BC Control Add-in rules:
/// - "procedure" = AL can call JS (AL → JS direction)
/// - "event"     = JS can call AL (JS → AL direction)
/// - There is NO built-in "OnControlReady" trigger. Instead we define
///   our own "OnReady" event that JS fires via InvokeExtensibilityMethod.
/// - On the page, the usercontrol triggers are wired to the EVENTS, not procedures.
/// </summary>
controladdin DependencyGraph
{
    // Startup script: builds DOM, loads vis.js from CDN, fires OnReady event
    StartupScript = 'src/controladdin/DependencyGraph/js/startup.js';

    // Main app logic: graph rendering, filtering, detail panel
    Scripts = 'src/controladdin/DependencyGraph/js/app.js';

    // Dark theme styles
    StyleSheets = 'src/controladdin/DependencyGraph/css/style.css';

    RequestedHeight = 600;
    MinimumHeight = 400;
    RequestedWidth = 1200;
    MinimumWidth = 600;
    VerticalStretch = true;
    HorizontalStretch = true;

    // ── AL → JS (procedures) ────────────────────────────────────────
    // These become callable from AL via CurrPage.ControlName.ProcedureName()
    // In JS, they appear as window.ProcedureName(args) functions

    /// <summary>Sends the JSON payload containing nodes and edges to JS for rendering.</summary>
    procedure LoadGraph(JsonPayload: Text);

    /// <summary>Programmatically highlights a specific node by App ID.</summary>
    procedure HighlightNode(AppId: Text);

    // ── JS → AL (events) ────────────────────────────────────────────
    // These are fired from JS via Microsoft.Dynamics.NAV.InvokeExtensibilityMethod()
    // On the page, they appear as triggers inside the usercontrol block

    /// <summary>
    /// Fired by JS once vis.js is loaded and DOM is ready.
    /// This is our replacement for the non-existent "OnControlReady".
    /// </summary>
    event OnReady();

    /// <summary>Fired when the user clicks a node in the graph.</summary>
    event OnNodeSelected(AppId: Text; AppName: Text; Publisher: Text; Version: Text);
}
