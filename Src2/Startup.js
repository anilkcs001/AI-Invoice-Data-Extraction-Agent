/**
 * @file startup.js
 * @description Bootstrap — builds DOM, loads vis.js, fires OnReady to AL.
 * No physics. Static hierarchical flowchart layout.
 */
(function () {
    "use strict";

    function loadScript(url) {
        return new Promise(function (resolve, reject) {
            var existing = document.querySelector('script[src="' + url + '"]');
            if (existing) {
                if (typeof vis !== "undefined") { resolve(); return; }
                existing.addEventListener("load", resolve);
                existing.addEventListener("error", function () { reject(new Error("Failed: " + url)); });
                return;
            }
            var s = document.createElement("script");
            s.src = url;
            s.async = true;
            s.onload = resolve;
            s.onerror = function () { reject(new Error("Failed to load: " + url)); };
            document.head.appendChild(s);
        });
    }

    function loadCSS(url) {
        if (document.querySelector('link[href="' + url + '"]')) return;
        var link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = url;
        document.head.appendChild(link);
    }

    function buildDOM() {
        var container = document.getElementById("controlAddIn");
        if (!container) container = document.body;
        container.className = "dg-root dg-light";

        container.innerHTML = [
            '<div class="dg-topbar">',
            '  <div class="dg-topbar-left">',
            '    <svg class="dg-logo-icon" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2">',
            '      <circle cx="5" cy="6" r="2"/><circle cx="12" cy="18" r="2"/>',
            '      <circle cx="19" cy="6" r="2"/><line x1="5" y1="8" x2="12" y2="16"/>',
            '      <line x1="19" y1="8" x2="12" y2="16"/>',
            '    </svg>',
            '    <h1 class="dg-title">Extension Dependency Graph</h1>',
            '  </div>',
            '  <div class="dg-topbar-right">',
            '    <span class="dg-stat" id="dgStatNodes"><strong id="dgStatNodesNum">0</strong> Extensions</span>',
            '    <span class="dg-stat" id="dgStatEdges"><strong id="dgStatEdgesNum">0</strong> Dependencies</span>',
            '    <button class="dg-theme-btn" id="dgThemeToggle" title="Toggle Dark/Light Mode">',
            '      <span class="dg-theme-icon" id="dgThemeIcon">&#9790;</span>',
            '    </button>',
            '  </div>',
            '</div>',

            '<div class="dg-filters" id="dgFilters">',
            '  <button class="dg-pill dg-pill-active" data-type="all">All</button>',
            '  <button class="dg-pill" data-type="ms">Microsoft</button>',
            '  <button class="dg-pill" data-type="isv">ISV</button>',
            '  <button class="dg-pill" data-type="custom">Custom</button>',
            '  <button class="dg-pill" data-type="ext">Third Party</button>',
            '</div>',

            '<div class="dg-main">',
            '  <div class="dg-graph-wrap" id="dgGraphWrap">',
            '    <div id="dgNetwork" class="dg-network"></div>',
            '    <div class="dg-graph-hint" id="dgGraphHint">Loading graph data…</div>',
            '  </div>',

            '  <div class="dg-detail" id="dgDetail">',
            '    <button class="dg-detail-close" id="dgDetailClose" title="Close">&#x2715;</button>',
            '    <div class="dg-detail-header">',
            '      <div class="dg-detail-name" id="dgDetailName"></div>',
            '      <div class="dg-detail-meta">',
            '        <span class="dg-badge dg-badge-publisher" id="dgDetailPublisher"></span>',
            '        <span class="dg-badge dg-badge-version" id="dgDetailVersion"></span>',
            '      </div>',
            '      <span class="dg-badge dg-badge-type" id="dgDetailType"></span>',
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
            '</div>',

            '<div class="dg-legend" id="dgLegend">',
            '  <span class="dg-legend-item"><span class="dg-legend-dot" style="background:#3b82f6"></span>Microsoft</span>',
            '  <span class="dg-legend-item"><span class="dg-legend-dot" style="background:#10b981"></span>ISV</span>',
            '  <span class="dg-legend-item"><span class="dg-legend-dot" style="background:#f43f5e"></span>Custom</span>',
            '  <span class="dg-legend-item"><span class="dg-legend-dot" style="background:#8b5cf6"></span>Third Party</span>',
            '</div>'
        ].join("\n");
    }

    buildDOM();
    loadCSS("https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap");

    loadScript("https://unpkg.com/vis-network@9.1.9/standalone/umd/vis-network.min.js")
        .then(function () {
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnReady", []);
        })
        .catch(function (err) {
            var hint = document.getElementById("dgGraphHint");
            if (hint) {
                hint.textContent = "Error loading graph library: " + err.message;
                hint.style.color = "#ef4444";
            }
        });
})();
