/// <summary>
/// Control Add-in that hosts an interactive vis.js-based dependency graph
/// for visualizing extension relationships within Business Central.
/// </summary>
controladdin DependencyGraph
{
    // The startup script loads vis.js from CDN, builds the DOM scaffold,
    // and fires the OnReady callback once initialisation is complete.
    StartupScript = 'src/controladdin/DependencyGraph/js/startup.js';

    // Main application logic – graph rendering, filtering, detail panel.
    Scripts = 'src/controladdin/DependencyGraph/js/app.js';

    // Dark-theme styling, frosted-glass panel, filter pills, dot-grid bg.
    StyleSheets = 'src/controladdin/DependencyGraph/css/style.css';

    RequestedHeight = 600;
    MinimumHeight = 400;
    RequestedWidth = 1200;
    MinimumWidth = 600;
    VerticalStretch = true;
    HorizontalStretch = true;

    // ── AL → JS procedures ──────────────────────────────────────────────
    /// <summary>Sends the full nodes+edges JSON payload to the JS layer for rendering.</summary>
    procedure LoadGraph(JsonPayload: Text);

    /// <summary>Programmatically highlights a specific node by its App ID.</summary>
    procedure HighlightNode(AppId: Text);

    // ── JS → AL events (callbacks) ──────────────────────────────────────
    /// <summary>Fired by JS once the control add-in DOM and vis.js are fully initialised.</summary>
    event OnReady();

    /// <summary>Fired when a user clicks a node in the graph.</summary>
    event OnNodeSelected(AppId: Text; AppName: Text; Publisher: Text; Version: Text);
}