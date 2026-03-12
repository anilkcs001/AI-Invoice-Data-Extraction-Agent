/**
 * @file startup.js
 * @description StartupScript — builds DOM, loads fonts, fires OnReady to AL.
 * Runs automatically when the BC iframe loads. No vis.js needed.
 */
(function () {
    "use strict";

    function loadCSS(url) {
        if (document.querySelector('link[href="' + url + '"]')) return;
        var link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = url;
        document.head.appendChild(link);
    }

    function buildDOM() {
        var c = document.getElementById("controlAddIn");
        if (!c) c = document.body;
        c.className = "ia-root ia-dark";

        c.innerHTML =
            // ── Top Bar ─────────────────────────────────────────
            '<div class="ia-topbar">' +
            '  <div class="ia-topbar-left">' +
            '    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#f59e0b" stroke-width="2">' +
            '      <path d="M12 9v4m0 4h.01M5.07 19h13.86c1.5 0 2.47-1.6 1.73-2.88L13.73 4.24c-.74-1.28-2.72-1.28-3.46 0L3.34 16.12C2.6 17.4 3.57 19 5.07 19z"/>' +
            '    </svg>' +
            '    <div>' +
            '      <h1 class="ia-title">Extension Impact Analyzer</h1>' +
            '      <p class="ia-subtitle">Analyze version update risks before publishing</p>' +
            '    </div>' +
            '  </div>' +
            '  <div class="ia-topbar-right">' +
            '    <span class="ia-stat"><strong id="iaStatNum">0</strong> extensions installed</span>' +
            '    <button class="ia-theme-btn" id="iaThemeToggle" title="Toggle theme">' +
            '      <span id="iaThemeIcon">&#9788;</span>' +
            '    </button>' +
            '  </div>' +
            '</div>' +

            // ── Body ────────────────────────────────────────────
            '<div class="ia-body">' +

            // ── Input Panel ─────────────────────────────────────
            '  <div class="ia-input-panel">' +
            '    <div class="ia-input-row">' +

            // Picker
            '      <div class="ia-picker-wrap">' +
            '        <label class="ia-label">Select Extension to Update</label>' +
            '        <div class="ia-picker" id="iaPicker">' +
            '          <div class="ia-picker-trigger" id="iaPickerTrigger">' +
            '            <span class="ia-picker-text">Choose an extension...</span>' +
            '            <svg class="ia-picker-arrow" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>' +
            '          </div>' +
            '          <div class="ia-picker-dropdown ia-hidden" id="iaPickerDropdown">' +
            '            <input class="ia-picker-search" id="iaPickerSearch" type="text" placeholder="Search extensions..." autocomplete="off" spellcheck="false"/>' +
            '            <div class="ia-picker-list" id="iaPickerList"></div>' +
            '          </div>' +
            '        </div>' +
            '        <div class="ia-current-ver ia-hidden" id="iaCurrentVer"></div>' +
            '      </div>' +

            // Version inputs
            '      <div class="ia-version-wrap">' +
            '        <label class="ia-label">New Version to Publish</label>' +
            '        <div class="ia-ver-inputs">' +
            '          <input class="ia-ver-part" id="iaMajor" type="number" min="0" value="0" />' +
            '          <span class="ia-ver-dot">.</span>' +
            '          <input class="ia-ver-part" id="iaMinor" type="number" min="0" value="0" />' +
            '          <span class="ia-ver-dot">.</span>' +
            '          <input class="ia-ver-part" id="iaBuild" type="number" min="0" value="0" />' +
            '          <span class="ia-ver-dot">.</span>' +
            '          <input class="ia-ver-part" id="iaRevision" type="number" min="0" value="0" />' +
            '        </div>' +
            '        <div class="ia-ver-preview" id="iaVerPreview">New version: 0.0.0.0</div>' +
            '        <div class="ia-ver-error ia-hidden" id="iaVerError"></div>' +
            '      </div>' +

            '    </div>' +

            // Analyze button
            '    <button class="ia-analyze-btn" id="iaAnalyzeBtn" disabled>' +
            '      <span class="ia-btn-text">Analyze Impact</span>' +
            '      <span class="ia-btn-spinner ia-hidden" id="iaBtnSpinner"></span>' +
            '    </button>' +

            '  </div>' +

            // ── Results Panel ───────────────────────────────────
            '  <div class="ia-results ia-hidden" id="iaResults">' +
            '    <div class="ia-risk-banner" id="iaRiskBanner"></div>' +
            '    <div class="ia-summary-row" id="iaSummary"></div>' +
            '    <div class="ia-filter-row" id="iaFilterRow"></div>' +
            '    <div class="ia-dep-list" id="iaDepList"></div>' +
            '  </div>' +

            '</div>';
    }

    buildDOM();
    loadCSS("https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Syne:wght@700;800&display=swap");

    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnReady", []);
})();