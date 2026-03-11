/**
 * @file startup.js
 * @description StartupScript — runs first.
 * Builds the DOM, loads fonts + vis.js, then fires OnReady to AL.
 * After this, app.js functions become available but do NOT auto-execute.
 */
(function () {
    "use strict";

    function loadScript(url) {
        return new Promise(function (resolve, reject) {
            var existing = document.querySelector('script[src="' + url + '"]');
            if (existing && typeof vis !== "undefined") { resolve(); return; }
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
        var c = document.getElementById("controlAddIn");
        if (!c) c = document.body;
        c.className = "dg-root dg-light";

        c.innerHTML =
            '<div class="dg-topbar">' +
            '  <div class="dg-topbar-left">' +
            '    <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="#3b82f6" stroke-width="2">' +
            '      <circle cx="5" cy="6" r="2"/><circle cx="12" cy="18" r="2"/>' +
            '      <circle cx="19" cy="6" r="2"/><line x1="5" y1="8" x2="12" y2="16"/>' +
            '      <line x1="19" y1="8" x2="12" y2="16"/>' +
            '    </svg>' +
            '    <h1 class="dg-title">Extension Dependencies</h1>' +
            '  </div>' +
            '  <div class="dg-topbar-right">' +
            '    <span class="dg-stat"><strong id="dgStatNum">0</strong>&nbsp;extensions</span>' +
            '    <button class="dg-theme-btn" id="dgThemeToggle" title="Toggle theme">' +
            '      <span id="dgThemeIcon">&#9790;</span>' +
            '    </button>' +
            '  </div>' +
            '</div>' +

            '<div class="dg-body">' +

            '  <div class="dg-list-panel">' +
            '    <div class="dg-search-wrap">' +
            '      <input type="text" class="dg-search" id="dgSearch" placeholder="Search extensions..." />' +
            '    </div>' +
            '    <div class="dg-filter-row" id="dgFilterRow">' +
            '      <button class="dg-fbtn dg-fbtn-on" data-type="all">All</button>' +
            '      <button class="dg-fbtn" data-type="ms">Microsoft</button>' +
            '      <button class="dg-fbtn" data-type="isv">ISV</button>' +
            '      <button class="dg-fbtn" data-type="custom">Custom</button>' +
            '      <button class="dg-fbtn" data-type="ext">3rd Party</button>' +
            '    </div>' +
            '    <div class="dg-extlist" id="dgExtList"></div>' +
            '  </div>' +

            '  <div class="dg-right">' +
            '    <div class="dg-placeholder" id="dgPlaceholder">' +
            '      <p>&#8592; Select an extension to view its dependency chain</p>' +
            '    </div>' +
            '    <div class="dg-detail" id="dgDetail" style="display:none;">' +
            '      <div class="dg-det-head">' +
            '        <div class="dg-det-name" id="dgDetName"></div>' +
            '        <div class="dg-det-meta">' +
            '          <span class="dg-tag" id="dgDetPub"></span>' +
            '          <span class="dg-tag dg-tag-ver" id="dgDetVer"></span>' +
            '          <span class="dg-tag dg-tag-type" id="dgDetType"></span>' +
            '        </div>' +
            '      </div>' +
            '      <div class="dg-tabs" id="dgTabs">' +
            '        <button class="dg-tab dg-tab-on" data-tab="order">Install Order</button>' +
            '        <button class="dg-tab" data-tab="tree">Tree View</button>' +
            '        <button class="dg-tab" data-tab="depby">Required By</button>' +
            '      </div>' +
            '      <div class="dg-tab-body" id="dgTabBody"></div>' +
            '    </div>' +
            '  </div>' +

            '</div>';
    }

    // Execute
    buildDOM();
    loadCSS("https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap");

    loadScript("https://unpkg.com/vis-network@9.1.9/standalone/umd/vis-network.min.js")
        .then(function () {
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnReady", []);
        })
        .catch(function (err) {
            var c = document.getElementById("controlAddIn");
            if (c) c.innerHTML = '<p style="padding:40px;color:red;">Failed to load graph library: ' + err.message + '</p>';
        });
})();
