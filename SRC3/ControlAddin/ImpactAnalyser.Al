/// <summary>
/// Control Add-in for the Extension Update Impact Analyzer.
/// Hosts a vanilla JS + CSS UI inside a BC iframe.
/// </summary>
controladdin ImpactAnalyzer
{
    StartupScript = 'src/controladdin/ImpactAnalyzer/js/startup.js';
    Scripts = 'src/controladdin/ImpactAnalyzer/js/app.js';
    StyleSheets = 'src/controladdin/ImpactAnalyzer/css/style.css';

    RequestedHeight = 700;
    MinimumHeight = 500;
    RequestedWidth = 1200;
    MinimumWidth = 700;
    VerticalStretch = true;
    HorizontalStretch = true;

    // ── AL → JS procedures ──────────────────────────────────────
    /// <summary>Sends the full list of installed extensions to JS for the picker dropdown.</summary>
    procedure LoadExtensions(JsonPayload: Text);

    /// <summary>Sends the computed impact analysis result to JS for rendering.</summary>
    procedure ShowImpactResult(JsonPayload: Text);

    /// <summary>Tells JS to show or hide a loading spinner during AL computation.</summary>
    procedure SetAnalyzing(IsAnalyzing: Boolean);

    // ── JS → AL events ──────────────────────────────────────────
    /// <summary>Fired by JS once DOM is built and ready to receive data.</summary>
    event OnReady();

    /// <summary>Fired when user clicks Analyze Impact button.</summary>
    event OnAnalyzeRequested(AppId: Text; NewVersionMajor: Integer;
                             NewVersionMinor: Integer; NewVersionBuild: Integer;
                             NewVersionRevision: Integer);

    /// <summary>Fired when user picks an extension from the dropdown.</summary>
    event OnExtensionSelected(AppId: Text; AppName: Text; CurrentVersion: Text);
}