/**
 * @file app.js
 * @description Clean two-panel dependency viewer.
 *
 * LEFT PANEL: Searchable, filterable list of all extensions.
 * RIGHT PANEL: For the selected extension, shows:
 *   - Installation Order (what to install first, in numbered steps)
 *   - Tree View (small, focused graph — ONLY this extension's chain)
 *   - Required By (which extensions depend on this one)
 *
 * No more 125-node spaghetti. One extension at a time. Clean and human.
 */
(function () {
    "use strict";

    // ═══════════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════════
    var allNodes = [];
    var allEdges = [];
    var nodeMap = {};
    var depsOf = {};       // id → [ids this depends on]
    var requiredBy = {};   // id → [ids that depend on this]
    var selectedId = null;
    var activeFilter = "all";
    var searchText = "";
    var isDarkMode = false;
    var network = null;
    var activeTab = "order";

    var TYPE_COLORS = {
        ms: "#3b82f6",
        isv: "#10b981",
        custom: "#f43f5e",
        ext: "#8b5cf6"
    };
    var TYPE_LABELS = {
        ms: "Microsoft",
        isv: "ISV",
        custom: "Custom",
        ext: "3rd Party"
    };

    // ═══════════════════════════════════════════════════════════════════
    // window.LoadGraph — called by AL
    // ═══════════════════════════════════════════════════════════════════
    window.LoadGraph = function (jsonPayload) {
        var data;
        try { data = JSON.parse(jsonPayload); }
        catch (e) { return; }

        if (!data || !data.nodes) return;
        if (!data.edges) data.edges = [];

        allNodes = data.nodes;
        allEdges = data.edges;

        // Build lookups
        nodeMap = {};
        depsOf = {};
        requiredBy = {};

        var i;
        for (i = 0; i < allNodes.length; i++) {
            nodeMap[allNodes[i].id] = allNodes[i];
            depsOf[allNodes[i].id] = [];
            requiredBy[allNodes[i].id] = [];
        }
        for (i = 0; i < allEdges.length; i++) {
            var e = allEdges[i];
            if (depsOf[e.from]) depsOf[e.from].push(e.to);
            if (requiredBy[e.to]) requiredBy[e.to].push(e.from);
        }

        // Sort nodes alphabetically
        allNodes.sort(function (a, b) {
            return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
        });

        // Update stats
        var stat = document.getElementById("dgStatTotalNum");
        if (stat) stat.textContent = String(allNodes.length);

        // Render list
        selectedId = null;
        renderExtList();
        showEmptyState();
    };

    // ═══════════════════════════════════════════════════════════════════
    // window.HighlightNode — called by AL
    // ═══════════════════════════════════════════════════════════════════
    window.HighlightNode = function (appId) {
        if (!appId || !nodeMap[appId]) return;
        selectExtension(appId);
    };

    // ═══════════════════════════════════════════════════════════════════
    // Extension List (left panel)
    // ═══════════════════════════════════════════════════════════════════

    function renderExtList() {
        var container = document.getElementById("dgExtList");
        if (!container) return;

        var filtered = allNodes.filter(function (n) {
            // Filter by type
            if (activeFilter !== "all" && n.type !== activeFilter) return false;
            // Filter by search
            if (searchText) {
                var q = searchText.toLowerCase();
                if (n.name.toLowerCase().indexOf(q) === -1 &&
                    n.publisher.toLowerCase().indexOf(q) === -1) return false;
            }
            return true;
        });

        if (filtered.length === 0) {
            container.innerHTML = '<div class="dg-ext-list-empty">No extensions match your search</div>';
            return;
        }

        var html = [];
        for (var i = 0; i < filtered.length; i++) {
            var n = filtered[i];
            var isActive = (n.id === selectedId);
            var depCount = (depsOf[n.id] || []).length;
            var reqCount = (requiredBy[n.id] || []).length;

            html.push(
                '<button class="dg-ext-item' + (isActive ? ' dg-ext-item-active' : '') + '" data-id="' + n.id + '">',
                '  <span class="dg-ext-dot" style="background:' + (TYPE_COLORS[n.type] || '#8b5cf6') + '"></span>',
                '  <div class="dg-ext-info">',
                '    <div class="dg-ext-name">' + escapeHtml(n.name) + '</div>',
                '    <div class="dg-ext-sub">' + escapeHtml(n.publisher) + ' &middot; v' + escapeHtml(n.version) + '</div>',
                '  </div>',
                '  <div class="dg-ext-badges">',
                (depCount > 0 ? '<span class="dg-ext-badge" title="Dependencies">' + depCount + ' dep' + (depCount > 1 ? 's' : '') + '</span>' : ''),
                (reqCount > 0 ? '<span class="dg-ext-badge dg-ext-badge-req" title="Required by">' + reqCount + ' req</span>' : ''),
                '  </div>',
                '</button>'
            );
        }

        container.innerHTML = html.join("");
    }

    function selectExtension(id) {
        if (!nodeMap[id]) return;
        selectedId = id;
        renderExtList(); // Re-render to show active state

        // Scroll the selected item into view
        var activeItem = document.querySelector('.dg-ext-item-active');
        if (activeItem) {
            activeItem.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }

        showDepView(id);

        // Fire callback to AL
        var node = nodeMap[id];
        try {
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnNodeSelected", [
                node.id || "", node.name || "", node.publisher || "", node.version || ""
            ]);
        } catch (ex) { /* ignore */ }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Dependency View (right panel)
    // ═══════════════════════════════════════════════════════════════════

    function showEmptyState() {
        var empty = document.getElementById("dgEmptyState");
        var view = document.getElementById("dgDepView");
        if (empty) empty.style.display = "flex";
        if (view) view.style.display = "none";
    }

    function showDepView(id) {
        var empty = document.getElementById("dgEmptyState");
        var view = document.getElementById("dgDepView");
        if (empty) empty.style.display = "none";
        if (view) view.style.display = "flex";

        var node = nodeMap[id];
        if (!node) return;

        // Header
        setTextById("dgDepName", node.name);
        setTextById("dgDepPublisher", node.publisher);
        setTextById("dgDepVersion", "v" + node.version);

        var typeEl = document.getElementById("dgDepType");
        if (typeEl) {
            typeEl.textContent = TYPE_LABELS[node.type] || "Extension";
            typeEl.style.backgroundColor = TYPE_COLORS[node.type] || TYPE_COLORS.ext;
        }

        // Show active tab content
        switchTab(activeTab);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Tab: Installation Order
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Computes the full installation order using topological sort (BFS/DFS).
     * Returns an array of node ids in the order they should be installed
     * (deepest dependency first, selected extension last).
     */
    function getInstallOrder(rootId) {
        var visited = {};
        var order = [];

        function dfs(id) {
            if (visited[id]) return;
            visited[id] = true;
            var deps = depsOf[id] || [];
            for (var i = 0; i < deps.length; i++) {
                if (nodeMap[deps[i]]) {
                    dfs(deps[i]);
                }
            }
            order.push(id);
        }

        dfs(rootId);
        return order;
    }

    function renderInstallOrder() {
        if (!selectedId) return;

        var order = getInstallOrder(selectedId);
        var infoEl = document.getElementById("dgOrderInfo");
        var listEl = document.getElementById("dgOrderList");
        if (!infoEl || !listEl) return;

        if (order.length <= 1) {
            infoEl.textContent = "This extension has no dependencies. Install it directly.";
            listEl.innerHTML = renderOrderItem(selectedId, 1, order.length, true);
            return;
        }

        infoEl.textContent = "Install these " + order.length + " extensions in order (first to last):";

        var html = [];
        for (var i = 0; i < order.length; i++) {
            var isRoot = (order[i] === selectedId);
            html.push(renderOrderItem(order[i], i + 1, order.length, isRoot));
        }
        listEl.innerHTML = html.join("");
    }

    function renderOrderItem(id, step, total, isRoot) {
        var n = nodeMap[id];
        if (!n) return "";

        var color = TYPE_COLORS[n.type] || TYPE_COLORS.ext;
        var depCount = (depsOf[id] || []).length;

        return [
            '<div class="dg-order-item' + (isRoot ? ' dg-order-item-root' : '') + '" data-id="' + id + '">',
            '  <div class="dg-order-step">' + step + '</div>',
            '  <div class="dg-order-line' + (step === total ? ' dg-order-line-last' : '') + '"></div>',
            '  <div class="dg-order-card">',
            '    <div class="dg-order-card-top">',
            '      <span class="dg-order-dot" style="background:' + color + '"></span>',
            '      <span class="dg-order-name">' + escapeHtml(n.name) + '</span>',
            '      <span class="dg-order-type" style="background:' + color + '">' + (TYPE_LABELS[n.type] || "Ext") + '</span>',
            '    </div>',
            '    <div class="dg-order-card-bottom">',
            '      <span>' + escapeHtml(n.publisher) + '</span>',
            '      <span>v' + escapeHtml(n.version) + '</span>',
            (depCount > 0 ? '<span>' + depCount + ' dep' + (depCount > 1 ? 's' : '') + '</span>' : ''),
            '    </div>',
            (isRoot ? '<div class="dg-order-root-label">&#9733; Selected Extension</div>' : ''),
            '  </div>',
            '</div>'
        ].join("");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Tab: Tree View (focused graph — only the selected extension's deps)
    // ═══════════════════════════════════════════════════════════════════

    function renderTreeView() {
        if (!selectedId) return;

        var container = document.getElementById("dgTreeGraph");
        if (!container) return;

        if (network) { network.destroy(); network = null; }

        // Get all nodes in the dependency chain
        var chainIds = {};
        function collectDeps(id) {
            if (chainIds[id]) return;
            chainIds[id] = true;
            var deps = depsOf[id] || [];
            for (var i = 0; i < deps.length; i++) {
                if (nodeMap[deps[i]]) collectDeps(deps[i]);
            }
        }
        collectDeps(selectedId);

        // Also include nodes that directly depend on this (one level up)
        var reqBy = requiredBy[selectedId] || [];
        for (var r = 0; r < reqBy.length; r++) {
            if (nodeMap[reqBy[r]]) chainIds[reqBy[r]] = true;
        }

        // Build vis nodes
        var visNodes = [];
        var ids = Object.keys(chainIds);
        for (var i = 0; i < ids.length; i++) {
            var n = nodeMap[ids[i]];
            if (!n) continue;
            var isRoot = (ids[i] === selectedId);
            var baseColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;

            visNodes.push({
                id: n.id,
                label: truncate(n.name, 28),
                title: n.name + "\n" + n.publisher + "\nv" + n.version,
                color: {
                    background: isRoot ? "#f59e0b" : (isDarkMode ? darkenColor(baseColor, 0.7) : lightenColor(baseColor, 0.88)),
                    border: isRoot ? "#d97706" : baseColor,
                    highlight: { background: "#f59e0b", border: "#d97706" }
                },
                font: {
                    color: isRoot ? "#fff" : (isDarkMode ? "#e2e8f0" : "#1e293b"),
                    size: isRoot ? 13 : 12,
                    face: "'Inter', sans-serif",
                    bold: isRoot ? { color: "#fff" } : undefined
                },
                borderWidth: isRoot ? 3 : 2,
                shape: "box",
                margin: { top: 8, bottom: 8, left: 12, right: 12 },
                shadow: isRoot ? { enabled: true, color: "rgba(245,158,11,0.3)", size: 12 } : { enabled: true, color: "rgba(0,0,0,0.06)", size: 4 },
                widthConstraint: { minimum: 100, maximum: 220 }
            });
        }

        // Build vis edges (only for nodes in the chain)
        var visEdges = [];
        var edgeIdx = 0;
        for (var j = 0; j < allEdges.length; j++) {
            var e = allEdges[j];
            if (chainIds[e.from] && chainIds[e.to]) {
                visEdges.push({
                    id: "e" + edgeIdx++,
                    from: e.from,
                    to: e.to,
                    arrows: "to",
                    color: {
                        color: isDarkMode ? "rgba(148,163,184,0.35)" : "rgba(100,116,139,0.3)",
                        highlight: "#f59e0b"
                    },
                    width: 1.5,
                    smooth: { type: "cubicBezier", forceDirection: "vertical", roundness: 0.4 }
                });
            }
        }

        if (visNodes.length === 0) {
            container.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;height:100%;color:var(--dg-text-muted);font-size:14px;">No dependency tree to display</div>';
            return;
        }

        var nodesDS = new vis.DataSet(visNodes);
        var edgesDS = new vis.DataSet(visEdges);

        var options = {
            autoResize: true,
            layout: {
                hierarchical: {
                    enabled: true,
                    direction: "UD",
                    sortMethod: "directed",
                    levelSeparation: 90,
                    nodeSpacing: 160,
                    treeSpacing: 200,
                    blockShifting: true,
                    edgeMinimization: true,
                    parentCentralization: true,
                    shakeTowards: "roots"
                }
            },
            physics: { enabled: false },
            interaction: {
                hover: true,
                zoomView: true,
                dragView: true,
                dragNodes: false
            },
            nodes: {
                shape: "box",
                font: { size: 12, face: "'Inter', sans-serif" },
                borderWidth: 2,
                margin: { top: 8, bottom: 8, left: 12, right: 12 }
            },
            edges: {
                arrows: { to: { enabled: true, scaleFactor: 0.6 } },
                smooth: { type: "cubicBezier", forceDirection: "vertical", roundness: 0.4 }
            }
        };

        network = new vis.Network(container, { nodes: nodesDS, edges: edgesDS }, options);

        // Click a node in tree → select that extension
        network.on("click", function (params) {
            if (params.nodes && params.nodes.length > 0) {
                var clickedId = params.nodes[0];
                if (clickedId !== selectedId) {
                    selectExtension(clickedId);
                }
            }
        });

        setTimeout(function () {
            if (network) network.fit({ animation: { duration: 300, easingFunction: "easeInOutQuad" } });
        }, 200);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Tab: Required By
    // ═══════════════════════════════════════════════════════════════════

    function renderRequiredBy() {
        if (!selectedId) return;

        var reqs = (requiredBy[selectedId] || []).filter(function (id) { return !!nodeMap[id]; });
        var infoEl = document.getElementById("dgReqInfo");
        var listEl = document.getElementById("dgReqList");
        if (!infoEl || !listEl) return;

        if (reqs.length === 0) {
            infoEl.textContent = "No other extension depends on this one.";
            listEl.innerHTML = "";
            return;
        }

        // Sort alphabetically
        reqs.sort(function (a, b) {
            return (nodeMap[a].name || "").toLowerCase().localeCompare((nodeMap[b].name || "").toLowerCase());
        });

        infoEl.textContent = reqs.length + " extension" + (reqs.length > 1 ? "s" : "") + " depend" + (reqs.length === 1 ? "s" : "") + " on this:";

        var html = [];
        for (var i = 0; i < reqs.length; i++) {
            var n = nodeMap[reqs[i]];
            if (!n) continue;
            var color = TYPE_COLORS[n.type] || TYPE_COLORS.ext;
            html.push(
                '<button class="dg-req-item" data-id="' + n.id + '">',
                '  <span class="dg-order-dot" style="background:' + color + '"></span>',
                '  <div class="dg-req-info">',
                '    <div class="dg-req-name">' + escapeHtml(n.name) + '</div>',
                '    <div class="dg-req-sub">' + escapeHtml(n.publisher) + ' &middot; v' + escapeHtml(n.version) + '</div>',
                '  </div>',
                '  <span class="dg-order-type" style="background:' + color + '">' + (TYPE_LABELS[n.type] || "Ext") + '</span>',
                '</button>'
            );
        }
        listEl.innerHTML = html.join("");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Tab switching
    // ═══════════════════════════════════════════════════════════════════

    function switchTab(tab) {
        activeTab = tab;

        // Update tab buttons
        var tabs = document.querySelectorAll(".dg-tab");
        for (var i = 0; i < tabs.length; i++) {
            var t = tabs[i];
            if (t.getAttribute("data-tab") === tab) {
                t.classList.add("dg-tab-active");
            } else {
                t.classList.remove("dg-tab-active");
            }
        }

        // Show/hide content
        var orderEl = document.getElementById("dgTabOrder");
        var treeEl = document.getElementById("dgTabTree");
        var reqEl = document.getElementById("dgTabRequiredBy");

        if (orderEl) orderEl.style.display = (tab === "order") ? "block" : "none";
        if (treeEl) treeEl.style.display = (tab === "tree") ? "block" : "none";
        if (reqEl) reqEl.style.display = (tab === "requiredby") ? "block" : "none";

        // Render content for active tab
        if (tab === "order") renderInstallOrder();
        if (tab === "tree") {
            // Small delay to let container become visible before rendering
            setTimeout(renderTreeView, 50);
        }
        if (tab === "requiredby") renderRequiredBy();
    }

    // ═══════════════════════════════════════════════════════════════════
    // Theme Toggle
    // ═══════════════════════════════════════════════════════════════════

    function toggleTheme() {
        isDarkMode = !isDarkMode;
        var root = document.querySelector(".dg-root");
        if (root) {
            root.classList.toggle("dg-dark", isDarkMode);
            root.classList.toggle("dg-light", !isDarkMode);
        }
        var icon = document.getElementById("dgThemeIcon");
        if (icon) icon.innerHTML = isDarkMode ? "&#9788;" : "&#9790;";

        // Re-render tree if visible
        if (activeTab === "tree" && selectedId) {
            setTimeout(renderTreeView, 100);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Utilities
    // ═══════════════════════════════════════════════════════════════════

    function setTextById(id, text) {
        var el = document.getElementById(id);
        if (el) el.textContent = text || "";
    }

    function escapeHtml(str) {
        if (!str) return "";
        return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }

    function truncate(str, max) {
        if (!str) return "";
        return str.length > max ? str.substring(0, max - 1) + "\u2026" : str;
    }

    function lightenColor(hex, factor) {
        if (!hex || hex.charAt(0) !== "#") return hex;
        var num = parseInt(hex.slice(1), 16);
        var r = Math.round(((num >> 16) & 0xff) + (255 - ((num >> 16) & 0xff)) * factor);
        var g = Math.round(((num >> 8) & 0xff) + (255 - ((num >> 8) & 0xff)) * factor);
        var b = Math.round((num & 0xff) + (255 - (num & 0xff)) * factor);
        return "rgb(" + r + "," + g + "," + b + ")";
    }

    function darkenColor(hex, factor) {
        if (!hex || hex.charAt(0) !== "#") return hex;
        var num = parseInt(hex.slice(1), 16);
        var r = Math.round(((num >> 16) & 0xff) * factor);
        var g = Math.round(((num >> 8) & 0xff) * factor);
        var b = Math.round((num & 0xff) * factor);
        return "rgb(" + r + "," + g + "," + b + ")";
    }

    // ═══════════════════════════════════════════════════════════════════
    // Event Wiring
    // ═══════════════════════════════════════════════════════════════════

    // ── Extension list click ────────────────────────────────────────
    var extListEl = document.getElementById("dgExtList");
    if (extListEl) {
        extListEl.addEventListener("click", function (evt) {
            var target = evt.target;
            while (target && !target.classList.contains("dg-ext-item")) {
                if (target === extListEl) { target = null; break; }
                target = target.parentElement;
            }
            if (!target) return;
            var id = target.getAttribute("data-id");
            if (id) selectExtension(id);
        });
    }

    // ── Search ──────────────────────────────────────────────────────
    var searchEl = document.getElementById("dgSearch");
    if (searchEl) {
        searchEl.addEventListener("input", function () {
            searchText = searchEl.value.trim();
            renderExtList();
        });
    }

    // ── Filter buttons ──────────────────────────────────────────────
    var filterRow = document.getElementById("dgFilterRow");
    if (filterRow) {
        filterRow.addEventListener("click", function (evt) {
            var target = evt.target;
            while (target && !target.classList.contains("dg-filter-btn")) {
                if (target === filterRow) { target = null; break; }
                target = target.parentElement;
            }
            if (!target) return;
            var type = target.getAttribute("data-type");
            if (!type || type === activeFilter) return;

            activeFilter = type;

            // Update active state
            var btns = filterRow.querySelectorAll(".dg-filter-btn");
            for (var i = 0; i < btns.length; i++) {
                var btn = btns[i];
                var bt = btn.getAttribute("data-type");
                if (bt === type) {
                    btn.classList.add("dg-filter-active");
                    if (bt !== "all" && TYPE_COLORS[bt]) {
                        btn.style.backgroundColor = TYPE_COLORS[bt];
                        btn.style.color = "#fff";
                        btn.style.borderColor = TYPE_COLORS[bt];
                    } else {
                        btn.style.backgroundColor = "";
                        btn.style.color = "";
                        btn.style.borderColor = "";
                    }
                } else {
                    btn.classList.remove("dg-filter-active");
                    btn.style.backgroundColor = "";
                    btn.style.color = "";
                    btn.style.borderColor = "";
                }
            }

            renderExtList();
        });
    }

    // ── Tab bar ─────────────────────────────────────────────────────
    var tabBar = document.getElementById("dgTabBar");
    if (tabBar) {
        tabBar.addEventListener("click", function (evt) {
            var target = evt.target;
            while (target && !target.classList.contains("dg-tab")) {
                if (target === tabBar) { target = null; break; }
                target = target.parentElement;
            }
            if (!target) return;
            var tab = target.getAttribute("data-tab");
            if (tab) switchTab(tab);
        });
    }

    // ── Required By list click ──────────────────────────────────────
    var reqListEl = document.getElementById("dgReqList");
    if (reqListEl) {
        reqListEl.addEventListener("click", function (evt) {
            var target = evt.target;
            while (target && !target.classList.contains("dg-req-item")) {
                if (target === reqListEl) { target = null; break; }
                target = target.parentElement;
            }
            if (!target) return;
            var id = target.getAttribute("data-id");
            if (id) selectExtension(id);
        });
    }

    // ── Install order list click (click to navigate) ────────────────
    var orderListEl = document.getElementById("dgOrderList");
    if (orderListEl) {
        orderListEl.addEventListener("click", function (evt) {
            var target = evt.target;
            while (target && !target.classList.contains("dg-order-item")) {
                if (target === orderListEl) { target = null; break; }
                target = target.parentElement;
            }
            if (!target) return;
            var id = target.getAttribute("data-id");
            if (id && id !== selectedId) selectExtension(id);
        });
    }

    // ── Theme toggle ────────────────────────────────────────────────
    var themeBtn = document.getElementById("dgThemeToggle");
    if (themeBtn) {
        themeBtn.addEventListener("click", function () { toggleTheme(); });
    }

    // ── Resize ──────────────────────────────────────────────────────
    window.addEventListener("resize", function () {
        if (network) setTimeout(function () { network.redraw(); }, 150);
    });

})();
