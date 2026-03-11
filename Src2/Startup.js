/**
 * @file startup.js
 * @description Builds the two-panel UI, loads vis.js, fires OnReady.
 *
 * NEW UX: Left panel = extension list, Right panel = dependency chain for selected extension.
 * No more 125-node chaos. Clean, focused, human-friendly.
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
            // ── Top bar ─────────────────────────────────────────────
            '<div class="dg-topbar">',
            '  <div class="dg-topbar-left">',
            '    <svg class="dg-logo-icon" viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2">',
            '      <circle cx="5" cy="6" r="2"/><circle cx="12" cy="18" r="2"/>',
            '      <circle cx="19" cy="6" r="2"/><line x1="5" y1="8" x2="12" y2="16"/>',
            '      <line x1="19" y1="8" x2="12" y2="16"/>',
            '    </svg>',
            '    <h1 class="dg-title">Extension Dependencies</h1>',
            '  </div>',
            '  <div class="dg-topbar-right">',
            '    <span class="dg-stat" id="dgStatTotal"><strong id="dgStatTotalNum">0</strong> extensions</span>',
            '    <button class="dg-theme-btn" id="dgThemeToggle" title="Toggle theme">',
            '      <span id="dgThemeIcon">&#9790;</span>',
            '    </button>',
            '  </div>',
            '</div>',

            // ── Main two-panel layout ───────────────────────────────
            '<div class="dg-body">',

            // LEFT: Extension list
            '  <div class="dg-list-panel" id="dgListPanel">',
            '    <div class="dg-search-wrap">',
            '      <svg class="dg-search-icon" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>',
            '      <input type="text" class="dg-search" id="dgSearch" placeholder="Search extensions..." autocomplete="off" spellcheck="false"/>',
            '    </div>',
            '    <div class="dg-filter-row" id="dgFilterRow">',
            '      <button class="dg-filter-btn dg-filter-active" data-type="all">All</button>',
            '      <button class="dg-filter-btn" data-type="ms">Microsoft</button>',
            '      <button class="dg-filter-btn" data-type="isv">ISV</button>',
            '      <button class="dg-filter-btn" data-type="custom">Custom</button>',
            '      <button class="dg-filter-btn" data-type="ext">3rd Party</button>',
            '    </div>',
            '    <div class="dg-ext-list" id="dgExtList">',
            '      <div class="dg-ext-list-empty">Loading extensions...</div>',
            '    </div>',
            '  </div>',

            // RIGHT: Dependency view for selected extension
            '  <div class="dg-detail-panel" id="dgDetailPanel">',
            '    <div class="dg-empty-state" id="dgEmptyState">',
            '      <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.3">',
            '        <path d="M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2"/>',
            '        <rect x="9" y="3" width="6" height="4" rx="1"/>',
            '        <line x1="9" y1="12" x2="15" y2="12"/><line x1="9" y1="16" x2="13" y2="16"/>',
            '      </svg>',
            '      <p>Select an extension from the list to view its dependency chain</p>',
            '    </div>',

            '    <div class="dg-dep-view" id="dgDepView" style="display:none;">',
            // Header for selected extension
            '      <div class="dg-dep-header" id="dgDepHeader">',
            '        <div class="dg-dep-name" id="dgDepName"></div>',
            '        <div class="dg-dep-meta">',
            '          <span class="dg-tag dg-tag-publisher" id="dgDepPublisher"></span>',
            '          <span class="dg-tag dg-tag-version" id="dgDepVersion"></span>',
            '          <span class="dg-tag dg-tag-type" id="dgDepType"></span>',
            '        </div>',
            '      </div>',

            // Tab bar: Install Order | Tree View
            '      <div class="dg-tab-bar" id="dgTabBar">',
            '        <button class="dg-tab dg-tab-active" data-tab="order">',
            '          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>',
            '          Install Order',
            '        </button>',
            '        <button class="dg-tab" data-tab="tree">',
            '          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="5" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><line x1="12" y1="7" x2="5" y2="17"/><line x1="12" y1="7" x2="19" y2="17"/></svg>',
            '          Tree View',
            '        </button>',
            '        <button class="dg-tab" data-tab="requiredby">',
            '          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>',
            '          Required By',
            '        </button>',
            '      </div>',

            // Install order list
            '      <div class="dg-tab-content" id="dgTabOrder">',
            '        <div class="dg-order-info" id="dgOrderInfo"></div>',
            '        <div class="dg-order-list" id="dgOrderList"></div>',
            '      </div>',

            // Tree graph
            '      <div class="dg-tab-content" id="dgTabTree" style="display:none;">',
            '        <div id="dgTreeGraph" class="dg-tree-graph"></div>',
            '      </div>',

            // Required by list
            '      <div class="dg-tab-content" id="dgTabRequiredBy" style="display:none;">',
            '        <div class="dg-order-info" id="dgReqInfo"></div>',
            '        <div class="dg-order-list" id="dgReqList"></div>',
            '      </div>',

            '    </div>',
            '  </div>',
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
            console.error("Failed to load vis.js:", err);
        });
})();
