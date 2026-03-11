/**
 * @file startup.js
 * @description Bootstrap script for the Dependency Graph Control Add-in.
 *
 * Responsibilities:
 *  1. Build the full DOM scaffold (top bar, filter pills, graph canvas, detail panel).
 *  2. Load Google Fonts (DM Sans) from CDN.
 *  3. Load vis-network from unpkg CDN.
 *  4. Fire the OnReady() callback to AL once everything is initialised.
 *
 * This file runs as the StartupScript of the control add-in, so it executes
 * automatically when the iframe is created by the BC web client.
 */

(function () {
    "use strict";

    // ── Helper: dynamically load a <script> from a URL ──────────────────
    /**
     * Loads an external script by injecting a <script> tag.
     * @param {string} url - The CDN URL to load.
     * @returns {Promise<void>}
     */
    function loadScript(url) {
        return new Promise(function (resolve, reject) {
            // Avoid double-loading if the script tag already exists
            var existing = document.querySelector('script[src="' + url + '"]');
            if (existing) {
                resolve();
                return;
            }
            var s = document.createElement("script");
            s.src = url;
            s.async = true;
            s.onload = resolve;
            s.onerror = function () {
                reject(new Error("Failed to load script: " + url));
            };
            document.head.appendChild(s);
        });
    }

    /**
     * Loads a CSS stylesheet by injecting a <link> tag.
     * @param {string} url - The CDN URL for the stylesheet.
     */
    function loadCSS(url) {
        if (document.querySelector('link[href="' + url + '"]')) return;
        var link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = url;
        document.head.appendChild(link);
    }

    // ── Build the DOM scaffold ──────────────────────────────────────────
    /**
     * Constructs the entire UI skeleton inside the control add-in container.
     */
    function buildDOM() {
        var container = document.getElementById("controlAddIn");
        if (!container) {
            // Fallback: some BC versions use the body directly
            container = document.body;
        }
        container.className = "dg-root";

        container.innerHTML = [
            // ── Top bar ─────────────────────────────────────────────────
            '<div class="dg-topbar">',
            '  <div class="dg-topbar-left">',
            '    <svg class="dg-logo-icon" viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="2">',
            '      <circle cx="5" cy="6" r="2"/><circle cx="12" cy="18" r="2"/>',
            '      <circle cx="19" cy="6" r="2"/><line x1="5" y1="8" x2="12" y2="16"/>',
            '      <line x1="19" y1="8" x2="12" y2="16"/>',
            '    </svg>',
            '    <h1 class="dg-title">Extension Dependency Graph</h1>',
            '  </div>',
            '  <div class="dg-topbar-right">',
            '    <span class="dg-stat" id="dgStatNodes"><span class="dg-stat-num">0</span> Extensions</span>',
            '    <span class="dg-stat" id="dgStatEdges"><span class="dg-stat-num">0</span> Dependencies</span>',
            '  </div>',
            '</div>',

            // ── Filter pills ────────────────────────────────────────────
            '<div class="dg-filters" id="dgFilters">',
            '  <button class="dg-pill dg-pill-active" data-type="all">All</button>',
            '  <button class="dg-pill" data-type="ms">Microsoft</button>',
            '  <button class="dg-pill" data-type="isv">ISV</button>',
            '  <button class="dg-pill" data-type="custom">Custom</button>',
            '  <button class="dg-pill" data-type="ext">Third Party</button>',
            '</div>',

            // ── Main content area ───────────────────────────────────────
            '<div class="dg-main">',
            '  <div class="dg-graph-wrap" id="dgGraphWrap">',
            '    <div id="dgNetwork" class="dg-network"></div>',
            '    <div class="dg-graph-hint" id="dgGraphHint">Loading graph data…</div>',
            '  </div>',

            // ── Detail panel (hidden by default) ────────────────────────
            '  <div class="dg-detail" id="dgDetail">',
            '    <button class="dg-detail-close" id="dgDetailClose" title="Close">✕</button>',
            '    <div class="dg-detail-header">',
            '      <div class="dg-detail-name" id="dgDetailName">—</div>',
            '      <div class="dg-detail-meta">',
            '        <span class="dg-badge dg-badge-publisher" id="dgDetailPublisher">—</span>',
            '        <span class="dg-badge dg-badge-version" id="dgDetailVersion">—</span>',
            '      </div>',
            '      <span class="dg-badge dg-badge-type" id="dgDetailType">—</span>',
            '    </div>',
            '    <div class="dg-detail-section">',
            '      <h3 class="dg-detail-section-title">Depends On <span class="dg-count" id="dgDepsCount">0</span></h3>',
            '      <div class="dg-chip-list" id="dgDepsList"></div>',
            '    </div>',
            '    <div class="dg-detail-section">',
            '      <h3 class="dg-detail-section-title">Required By <span class="dg-count" id="dgReqCount">0</span></h3>',
            '      <div class="dg-chip-list" id="dgReqList"></div>',
            '    </div>',
            '  </div>',
            '</div>'
        ].join("\n");
    }

    // ── Initialise ──────────────────────────────────────────────────────
    buildDOM();

    // Load DM Sans from Google Fonts
    loadCSS("https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&display=swap");

    // Load vis-network from CDN, then signal readiness to AL
    loadScript("https://unpkg.com/vis-network@9.1.9/standalone/umd/vis-network.min.js")
        .then(function () {
            // Signal to AL that the control is ready to receive data
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnReady", []);
        })
        .catch(function (err) {
            var hint = document.getElementById("dgGraphHint");
            if (hint) {
                hint.textContent = "Error loading graph library: " + err.message;
                hint.style.color = "#f43f5e";
            }
            console.error("DependencyGraph startup error:", err);
        });
})();