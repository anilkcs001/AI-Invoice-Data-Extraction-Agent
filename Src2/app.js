/**
 * @file app.js
 * @description All logic for the dependency graph viewer.
 *
 * CRITICAL: All event wiring happens INSIDE wireEvents() called from LoadGraph,
 * because that is the first moment DOM exists AND data is ready.
 *
 * NEW: Filter pills inside Install Order and Tree View tabs to filter
 * dependency chain by type (All / Microsoft / ISV / Custom / 3rd Party).
 */
(function () {
    "use strict";

    // ═══════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════
    var allNodes = [];
    var allEdges = [];
    var nodeMap = {};
    var depsOf = {};
    var requiredBy = {};
    var selectedId = null;
    var activeFilter = "all";       // Left panel list filter
    var depFilter = "all";          // Install Order / Tree tab filter
    var searchText = "";
    var isDark = false;
    var activeTab = "order";
    var network = null;
    var eventsWired = false;

    var COLORS = {
        ms: "#3b82f6",
        isv: "#10b981",
        custom: "#f43f5e",
        ext: "#8b5cf6"
    };
    var LABELS = {
        ms: "Microsoft",
        isv: "ISV",
        custom: "Custom",
        ext: "3rd Party"
    };

    // ═══════════════════════════════════════════════════════════════
    // window.LoadGraph — called from AL
    // ═══════════════════════════════════════════════════════════════
    window.LoadGraph = function (jsonPayload) {
        var data;
        try {
            data = JSON.parse(jsonPayload);
        } catch (e) {
            console.error("LoadGraph parse error:", e);
            return;
        }
        if (!data || !data.nodes) {
            console.error("LoadGraph: no nodes");
            return;
        }
        if (!data.edges) data.edges = [];

        allNodes = data.nodes || [];
        allEdges = data.edges || [];

        nodeMap = {};
        depsOf = {};
        requiredBy = {};
        var i, n, e;
        for (i = 0; i < allNodes.length; i++) {
            n = allNodes[i];
            nodeMap[n.id] = n;
            depsOf[n.id] = [];
            requiredBy[n.id] = [];
        }
        for (i = 0; i < allEdges.length; i++) {
            e = allEdges[i];
            if (depsOf[e.from]) depsOf[e.from].push(e.to);
            if (requiredBy[e.to]) requiredBy[e.to].push(e.from);
        }

        allNodes.sort(function (a, b) {
            return (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase());
        });

        var statEl = document.getElementById("dgStatNum");
        if (statEl) statEl.textContent = String(allNodes.length);

        selectedId = null;
        activeFilter = "all";
        depFilter = "all";
        searchText = "";
        activeTab = "order";

        var searchEl = document.getElementById("dgSearch");
        if (searchEl) searchEl.value = "";

        resetFilterButtons("all");
        renderList();
        showPlaceholder();

        if (!eventsWired) {
            wireEvents();
            eventsWired = true;
        }
    };

    // ═══════════════════════════════════════════════════════════════
    // window.HighlightNode — called from AL
    // ═══════════════════════════════════════════════════════════════
    window.HighlightNode = function (appId) {
        if (appId && nodeMap[appId]) {
            doSelect(appId);
        }
    };

    // ═══════════════════════════════════════════════════════════════
    // RENDER THE EXTENSION LIST (left panel)
    // ═══════════════════════════════════════════════════════════════
    function renderList() {
        var container = document.getElementById("dgExtList");
        if (!container) return;

        var filtered = [];
        var i, n, q;
        q = searchText.toLowerCase();

        for (i = 0; i < allNodes.length; i++) {
            n = allNodes[i];
            if (activeFilter !== "all" && n.type !== activeFilter) continue;
            if (q !== "") {
                var nameMatch = (n.name || "").toLowerCase().indexOf(q) !== -1;
                var pubMatch = (n.publisher || "").toLowerCase().indexOf(q) !== -1;
                if (!nameMatch && !pubMatch) continue;
            }
            filtered.push(n);
        }

        if (filtered.length === 0) {
            container.innerHTML = '<div class="dg-empty-list">No extensions found</div>';
            return;
        }

        var html = "";
        for (i = 0; i < filtered.length; i++) {
            n = filtered[i];
            var isActive = (n.id === selectedId);
            var dc = (depsOf[n.id] || []).length;
            var rc = (requiredBy[n.id] || []).length;
            var col = COLORS[n.type] || COLORS.ext;

            html += '<div class="dg-item' + (isActive ? ' dg-item-on' : '') + '" data-id="' + esc(n.id) + '">';
            html += '<span class="dg-dot" style="background:' + col + '"></span>';
            html += '<div class="dg-item-info">';
            html += '<div class="dg-item-name">' + esc(n.name) + '</div>';
            html += '<div class="dg-item-sub">' + esc(n.publisher) + ' · v' + esc(n.version) + '</div>';
            html += '</div>';
            html += '<div class="dg-item-right">';
            if (dc > 0) html += '<span class="dg-badge-dep">' + dc + ' dep</span>';
            if (rc > 0) html += '<span class="dg-badge-req">' + rc + ' req</span>';
            html += '</div>';
            html += '</div>';
        }

        container.innerHTML = html;
    }

    // ═══════════════════════════════════════════════════════════════
    // SELECT AN EXTENSION
    // ═══════════════════════════════════════════════════════════════
    function doSelect(id) {
        if (!nodeMap[id]) return;
        selectedId = id;
        depFilter = "all"; // Reset dep filter on new selection

        renderList();

        setTimeout(function () {
            var activeEl = document.querySelector('.dg-item-on');
            if (activeEl) activeEl.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }, 50);

        showDetail(id);

        var nd = nodeMap[id];
        try {
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnNodeSelected", [
                nd.id || "", nd.name || "", nd.publisher || "", nd.version || ""
            ]);
        } catch (ex) { /* ok */ }
    }

    // ═══════════════════════════════════════════════════════════════
    // SHOW / HIDE PANELS
    // ═══════════════════════════════════════════════════════════════
    function showPlaceholder() {
        var ph = document.getElementById("dgPlaceholder");
        var det = document.getElementById("dgDetail");
        if (ph) ph.style.display = "flex";
        if (det) det.style.display = "none";
    }

    function showDetail(id) {
        var ph = document.getElementById("dgPlaceholder");
        var det = document.getElementById("dgDetail");
        if (ph) ph.style.display = "none";
        if (det) det.style.display = "flex";

        var nd = nodeMap[id];
        if (!nd) return;

        setText("dgDetName", nd.name);
        setText("dgDetPub", nd.publisher);
        setText("dgDetVer", "v" + nd.version);

        var typeEl = document.getElementById("dgDetType");
        if (typeEl) {
            typeEl.textContent = LABELS[nd.type] || "Extension";
            typeEl.style.backgroundColor = COLORS[nd.type] || COLORS.ext;
        }

        activeTab = "order";
        depFilter = "all";
        resetTabButtons("order");
        renderTabContent();
    }

    // ═══════════════════════════════════════════════════════════════
    // DEPENDENCY FILTER PILLS (shared by Install Order + Tree View)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Builds the HTML for the dependency filter pill bar.
     * Used inside Install Order and Tree View tabs.
     * @param {Object} counts - { all, ms, isv, custom, ext } counts
     * @returns {string} HTML string
     */
    function buildDepFilterBar(counts) {
        var types = [
            { key: "all", label: "All" },
            { key: "ms", label: "Microsoft" },
            { key: "isv", label: "ISV" },
            { key: "custom", label: "Custom" },
            { key: "ext", label: "3rd Party" }
        ];

        var html = '<div class="dg-dep-filters">';
        for (var i = 0; i < types.length; i++) {
            var t = types[i];
            var count = counts[t.key] || 0;
            var isOn = (depFilter === t.key);

            // Skip types with zero count (except "all")
            if (t.key !== "all" && count === 0) continue;

            var style = '';
            if (isOn && t.key !== "all" && COLORS[t.key]) {
                style = ' style="background:' + COLORS[t.key] + ';color:#fff;border-color:' + COLORS[t.key] + '"';
            }

            html += '<button class="dg-dep-pill' + (isOn ? ' dg-dep-pill-on' : '') + '" data-deptype="' + t.key + '"' + style + '>';
            html += t.label;
            html += '<span class="dg-dep-pill-count">' + (t.key === "all" ? counts.all : count) + '</span>';
            html += '</button>';
        }
        html += '</div>';
        return html;
    }

    /**
     * Counts how many items of each type are in a list of node IDs.
     * @param {string[]} ids - Array of node IDs
     * @returns {Object} { all, ms, isv, custom, ext }
     */
    function countTypes(ids) {
        var counts = { all: ids.length, ms: 0, isv: 0, custom: 0, ext: 0 };
        for (var i = 0; i < ids.length; i++) {
            var nd = nodeMap[ids[i]];
            if (nd && counts.hasOwnProperty(nd.type)) {
                counts[nd.type]++;
            }
        }
        return counts;
    }

    /**
     * Filters a list of node IDs by the current depFilter.
     * Always includes the selected extension regardless of filter.
     * @param {string[]} ids
     * @returns {string[]}
     */
    function filterByDepType(ids) {
        if (depFilter === "all") return ids;
        var result = [];
        for (var i = 0; i < ids.length; i++) {
            var nd = nodeMap[ids[i]];
            if (!nd) continue;
            // Always include the selected extension itself
            if (ids[i] === selectedId) {
                result.push(ids[i]);
                continue;
            }
            if (nd.type === depFilter) {
                result.push(ids[i]);
            }
        }
        return result;
    }

    // ═══════════════════════════════════════════════════════════════
    // TAB CONTENT RENDERING
    // ═══════════════════════════════════════════════════════════════
    function renderTabContent() {
        var body = document.getElementById("dgTabBody");
        if (!body || !selectedId) return;

        if (activeTab === "order") {
            renderInstallOrder(body);
        } else if (activeTab === "tree") {
            renderTreeView(body);
        } else if (activeTab === "depby") {
            renderRequiredBy(body);
        }
    }

    // ── Install Order ───────────────────────────────────────────
    function getInstallOrder(rootId) {
        var visited = {};
        var result = [];

        function dfs(id) {
            if (visited[id]) return;
            visited[id] = true;
            var deps = depsOf[id] || [];
            for (var i = 0; i < deps.length; i++) {
                if (nodeMap[deps[i]]) dfs(deps[i]);
            }
            result.push(id);
        }

        dfs(rootId);
        return result;
    }

    function renderInstallOrder(container) {
        if (!selectedId) return;

        var fullOrder = getInstallOrder(selectedId);
        var counts = countTypes(fullOrder);
        var filtered = filterByDepType(fullOrder);

        var html = '';

        // Filter pills
        html += buildDepFilterBar(counts);

        if (fullOrder.length <= 1) {
            html += '<div class="dg-info-msg">This extension has no dependencies. Install it directly.</div>';
            html += buildOrderCard(selectedId, 1, 1, true);
        } else {
            html += '<div class="dg-info-msg">Showing <strong>' + filtered.length + '</strong> of <strong>' + fullOrder.length + '</strong> extensions in install order:</div>';

            var step = 0;
            for (var i = 0; i < filtered.length; i++) {
                step++;
                html += buildOrderCard(filtered[i], step, filtered.length, filtered[i] === selectedId);
            }
        }

        container.innerHTML = html;

        // Wire clicks on order items
        wireOrderClicks(container);
        // Wire clicks on dep filter pills
        wireDepFilterClicks(container);
    }

    function buildOrderCard(id, step, total, isRoot) {
        var nd = nodeMap[id];
        if (!nd) return '';
        var col = COLORS[nd.type] || COLORS.ext;
        var isLast = (step === total);

        var s = '';
        s += '<div class="dg-ord' + (isRoot ? ' dg-ord-root' : '') + '" data-id="' + esc(id) + '">';

        s += '<div class="dg-ord-left">';
        s += '<div class="dg-ord-num' + (isRoot ? ' dg-ord-num-root' : '') + '">' + step + '</div>';
        if (!isLast) {
            s += '<div class="dg-ord-line"></div>';
        }
        s += '</div>';

        s += '<div class="dg-ord-card' + (isRoot ? ' dg-ord-card-root' : '') + '">';
        s += '<div class="dg-ord-row1">';
        s += '<span class="dg-dot" style="background:' + col + '"></span>';
        s += '<span class="dg-ord-name">' + esc(nd.name) + '</span>';
        s += '<span class="dg-type-pill" style="background:' + col + '">' + (LABELS[nd.type] || 'Ext') + '</span>';
        s += '</div>';
        s += '<div class="dg-ord-row2">' + esc(nd.publisher) + ' · v' + esc(nd.version) + '</div>';
        if (isRoot) s += '<div class="dg-ord-star">★ Selected Extension</div>';
        s += '</div>';

        s += '</div>';
        return s;
    }

    // ── Tree View ───────────────────────────────────────────────
    function renderTreeView(container) {
        if (!selectedId) return;

        if (network) { network.destroy(); network = null; }

        // Collect full chain
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

        var reqs = requiredBy[selectedId] || [];
        for (var r = 0; r < reqs.length; r++) {
            if (nodeMap[reqs[r]]) chainIds[reqs[r]] = true;
        }

        var allChainIds = Object.keys(chainIds);
        var counts = countTypes(allChainIds);

        // Apply dep filter
        var filteredIds = {};
        var filteredList = filterByDepType(allChainIds);
        for (var f = 0; f < filteredList.length; f++) {
            filteredIds[filteredList[f]] = true;
        }

        // Build HTML: filter bar + canvas
        var html = '';
        html += buildDepFilterBar(counts);
        html += '<div class="dg-tree-info">Showing <strong>' + filteredList.length + '</strong> of <strong>' + allChainIds.length + '</strong> extensions in dependency tree</div>';
        html += '<div id="dgTreeCanvas" class="dg-tree-canvas"></div>';
        container.innerHTML = html;

        // Wire dep filter clicks
        wireDepFilterClicks(container);

        if (filteredList.length === 0) {
            return;
        }

        // Build vis nodes
        var visNodes = [];
        for (var i = 0; i < filteredList.length; i++) {
            var nd = nodeMap[filteredList[i]];
            if (!nd) continue;
            var isRoot = (filteredList[i] === selectedId);
            var baseCol = COLORS[nd.type] || COLORS.ext;

            visNodes.push({
                id: nd.id,
                label: trunc(nd.name, 26),
                title: nd.name + '\n' + nd.publisher + '\nv' + nd.version,
                shape: "box",
                color: {
                    background: isRoot ? "#f59e0b" : (isDark ? darken(baseCol, 0.65) : lighten(baseCol, 0.85)),
                    border: isRoot ? "#d97706" : baseCol,
                    highlight: { background: "#f59e0b", border: "#d97706" }
                },
                font: {
                    color: isRoot ? "#fff" : (isDark ? "#e2e8f0" : "#1e293b"),
                    size: 12,
                    face: "'Inter', sans-serif"
                },
                borderWidth: isRoot ? 3 : 2,
                margin: { top: 8, bottom: 8, left: 12, right: 12 },
                shadow: {
                    enabled: true,
                    color: isRoot ? "rgba(245,158,11,0.25)" : "rgba(0,0,0,0.06)",
                    size: isRoot ? 12 : 4
                },
                widthConstraint: { minimum: 90, maximum: 200 }
            });
        }

        // Build vis edges (only where both nodes are visible)
        var visEdges = [];
        var eidx = 0;
        for (var j = 0; j < allEdges.length; j++) {
            var edge = allEdges[j];
            if (filteredIds[edge.from] && filteredIds[edge.to]) {
                visEdges.push({
                    id: "e" + eidx++,
                    from: edge.from,
                    to: edge.to,
                    arrows: "to",
                    color: {
                        color: isDark ? "rgba(148,163,184,0.3)" : "rgba(100,116,139,0.35)",
                        highlight: "#f59e0b"
                    },
                    width: 1.5,
                    smooth: { type: "cubicBezier", forceDirection: "vertical", roundness: 0.4 }
                });
            }
        }

        var treeContainer = document.getElementById("dgTreeCanvas");
        if (!treeContainer) return;

        var nds = new vis.DataSet(visNodes);
        var eds = new vis.DataSet(visEdges);

        network = new vis.Network(treeContainer, { nodes: nds, edges: eds }, {
            autoResize: true,
            layout: {
                hierarchical: {
                    enabled: true,
                    direction: "UD",
                    sortMethod: "directed",
                    levelSeparation: 90,
                    nodeSpacing: 150,
                    treeSpacing: 200,
                    parentCentralization: true,
                    shakeTowards: "roots"
                }
            },
            physics: { enabled: false },
            interaction: { hover: true, zoomView: true, dragView: true, dragNodes: false },
            nodes: { shape: "box", borderWidth: 2, margin: 8 },
            edges: { arrows: { to: { enabled: true, scaleFactor: 0.6 } } }
        });

        network.on("click", function (params) {
            if (params.nodes && params.nodes.length > 0) {
                var clicked = params.nodes[0];
                if (clicked !== selectedId) doSelect(clicked);
            }
        });

        setTimeout(function () {
            if (network) network.fit({ animation: { duration: 300, easingFunction: "easeInOutQuad" } });
        }, 200);
    }

    // ── Required By ─────────────────────────────────────────────
    function renderRequiredBy(container) {
        if (!selectedId) return;

        var reqs = (requiredBy[selectedId] || []).filter(function (id) { return !!nodeMap[id]; });

        if (reqs.length === 0) {
            container.innerHTML = '<div class="dg-info-msg">No other extension depends on this one.</div>';
            return;
        }

        reqs.sort(function (a, b) {
            return (nodeMap[a].name || "").toLowerCase().localeCompare((nodeMap[b].name || "").toLowerCase());
        });

        // Count types for required by
        var counts = countTypes(reqs);

        var html = '';
        html += buildDepFilterBar(counts);

        // Filter
        var filteredReqs = filterByDepType(reqs);

        html += '<div class="dg-info-msg"><strong>' + filteredReqs.length + '</strong> of <strong>' + reqs.length + '</strong> extension' + (reqs.length > 1 ? 's' : '') + ' depend' + (reqs.length === 1 ? 's' : '') + ' on this:</div>';

        for (var i = 0; i < filteredReqs.length; i++) {
            var nd = nodeMap[filteredReqs[i]];
            if (!nd) continue;
            var col = COLORS[nd.type] || COLORS.ext;
            html += '<div class="dg-reqitem" data-id="' + esc(nd.id) + '">';
            html += '<span class="dg-dot" style="background:' + col + '"></span>';
            html += '<div class="dg-reqitem-info">';
            html += '<div class="dg-reqitem-name">' + esc(nd.name) + '</div>';
            html += '<div class="dg-reqitem-sub">' + esc(nd.publisher) + ' · v' + esc(nd.version) + '</div>';
            html += '</div>';
            html += '<span class="dg-type-pill" style="background:' + col + '">' + (LABELS[nd.type] || 'Ext') + '</span>';
            html += '</div>';
        }

        container.innerHTML = html;

        // Wire clicks on items
        var items = container.querySelectorAll('.dg-reqitem');
        for (var j = 0; j < items.length; j++) {
            items[j].addEventListener('click', (function (el) {
                return function () {
                    var nid = el.getAttribute('data-id');
                    if (nid) doSelect(nid);
                };
            })(items[j]));
        }

        // Wire dep filter clicks
        wireDepFilterClicks(container);
    }

    // ═══════════════════════════════════════════════════════════════
    // WIRE DEP FILTER & ORDER CLICKS (reusable)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Attaches click listeners to dep filter pills inside a container.
     * On click, updates depFilter and re-renders the active tab.
     */
    function wireDepFilterClicks(container) {
        var pills = container.querySelectorAll('.dg-dep-pill');
        for (var i = 0; i < pills.length; i++) {
            pills[i].addEventListener('click', (function (el) {
                return function (evt) {
                    evt.stopPropagation();
                    var newType = el.getAttribute('data-deptype');
                    if (newType && newType !== depFilter) {
                        depFilter = newType;
                        renderTabContent();
                    }
                };
            })(pills[i]));
        }
    }

    /**
     * Attaches click listeners to order cards inside a container.
     */
    function wireOrderClicks(container) {
        var items = container.querySelectorAll('.dg-ord');
        for (var i = 0; i < items.length; i++) {
            items[i].addEventListener('click', (function (el) {
                return function () {
                    var nid = el.getAttribute('data-id');
                    if (nid && nid !== selectedId) doSelect(nid);
                };
            })(items[i]));
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // TAB SWITCHING
    // ═══════════════════════════════════════════════════════════════
    function switchTab(tab) {
        activeTab = tab;
        depFilter = "all"; // Reset dep filter when switching tabs
        resetTabButtons(tab);
        renderTabContent();
    }

    // ═══════════════════════════════════════════════════════════════
    // EVENT WIRING — called once from LoadGraph
    // ═══════════════════════════════════════════════════════════════
    function wireEvents() {

        // ── Extension list click ────────────────────────────────
        var listEl = document.getElementById("dgExtList");
        if (listEl) {
            listEl.addEventListener("click", function (evt) {
                var target = evt.target;
                var maxUp = 10;
                while (target && maxUp > 0) {
                    if (target.classList && target.classList.contains("dg-item")) {
                        var id = target.getAttribute("data-id");
                        if (id) doSelect(id);
                        return;
                    }
                    if (target === listEl) return;
                    target = target.parentElement;
                    maxUp--;
                }
            });
        }

        // ── Search ──────────────────────────────────────────────
        var searchEl = document.getElementById("dgSearch");
        if (searchEl) {
            searchEl.addEventListener("input", function () {
                searchText = (searchEl.value || "").trim();
                renderList();
            });
            searchEl.addEventListener("paste", function () {
                setTimeout(function () {
                    searchText = (searchEl.value || "").trim();
                    renderList();
                }, 10);
            });
        }

        // ── Left panel filter buttons ───────────────────────────
        var filterRow = document.getElementById("dgFilterRow");
        if (filterRow) {
            filterRow.addEventListener("click", function (evt) {
                var target = evt.target;
                var maxUp = 5;
                while (target && maxUp > 0) {
                    if (target.classList && target.classList.contains("dg-fbtn")) {
                        var type = target.getAttribute("data-type");
                        if (type && type !== activeFilter) {
                            activeFilter = type;
                            resetFilterButtons(type);
                            renderList();
                        }
                        return;
                    }
                    if (target === filterRow) return;
                    target = target.parentElement;
                    maxUp--;
                }
            });
        }

        // ── Tab buttons ─────────────────────────────────────────
        var tabsEl = document.getElementById("dgTabs");
        if (tabsEl) {
            tabsEl.addEventListener("click", function (evt) {
                var target = evt.target;
                var maxUp = 5;
                while (target && maxUp > 0) {
                    if (target.classList && target.classList.contains("dg-tab")) {
                        var tab = target.getAttribute("data-tab");
                        if (tab && tab !== activeTab) {
                            switchTab(tab);
                        }
                        return;
                    }
                    if (target === tabsEl) return;
                    target = target.parentElement;
                    maxUp--;
                }
            });
        }

        // ── Theme toggle ────────────────────────────────────────
        var themeBtn = document.getElementById("dgThemeToggle");
        if (themeBtn) {
            themeBtn.addEventListener("click", function () {
                isDark = !isDark;
                var root = document.querySelector(".dg-root");
                if (root) {
                    if (isDark) {
                        root.classList.remove("dg-light");
                        root.classList.add("dg-dark");
                    } else {
                        root.classList.remove("dg-dark");
                        root.classList.add("dg-light");
                    }
                }
                var icon = document.getElementById("dgThemeIcon");
                if (icon) icon.innerHTML = isDark ? "&#9788;" : "&#9790;";

                if ((activeTab === "tree") && selectedId) {
                    var body = document.getElementById("dgTabBody");
                    if (body) setTimeout(function () { renderTreeView(body); }, 50);
                }
            });
        }

        // ── Window resize ───────────────────────────────────────
        window.addEventListener("resize", function () {
            if (network) setTimeout(function () { network.redraw(); }, 100);
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════

    function resetFilterButtons(type) {
        var btns = document.querySelectorAll(".dg-fbtn");
        for (var i = 0; i < btns.length; i++) {
            var btn = btns[i];
            var bt = btn.getAttribute("data-type");
            if (bt === type) {
                btn.classList.add("dg-fbtn-on");
                if (bt !== "all" && COLORS[bt]) {
                    btn.style.backgroundColor = COLORS[bt];
                    btn.style.color = "#fff";
                    btn.style.borderColor = COLORS[bt];
                } else {
                    btn.style.backgroundColor = "";
                    btn.style.color = "";
                    btn.style.borderColor = "";
                }
            } else {
                btn.classList.remove("dg-fbtn-on");
                btn.style.backgroundColor = "";
                btn.style.color = "";
                btn.style.borderColor = "";
            }
        }
    }

    function resetTabButtons(tab) {
        var tabs = document.querySelectorAll(".dg-tab");
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].getAttribute("data-tab") === tab) {
                tabs[i].classList.add("dg-tab-on");
            } else {
                tabs[i].classList.remove("dg-tab-on");
            }
        }
    }

    function setText(id, val) {
        var el = document.getElementById(id);
        if (el) el.textContent = val || "";
    }

    function esc(str) {
        if (!str) return "";
        var d = document.createElement("div");
        d.appendChild(document.createTextNode(str));
        return d.innerHTML;
    }

    function trunc(str, max) {
        if (!str) return "";
        return str.length > max ? str.substring(0, max - 1) + "\u2026" : str;
    }

    function lighten(hex, factor) {
        if (!hex || hex[0] !== "#") return hex;
        var n = parseInt(hex.slice(1), 16);
        var r = Math.round(((n >> 16) & 0xff) + (255 - ((n >> 16) & 0xff)) * factor);
        var g = Math.round(((n >> 8) & 0xff) + (255 - ((n >> 8) & 0xff)) * factor);
        var b = Math.round((n & 0xff) + (255 - (n & 0xff)) * factor);
        return "rgb(" + r + "," + g + "," + b + ")";
    }

    function darken(hex, factor) {
        if (!hex || hex[0] !== "#") return hex;
        var n = parseInt(hex.slice(1), 16);
        return "rgb(" +
            Math.round(((n >> 16) & 0xff) * factor) + "," +
            Math.round(((n >> 8) & 0xff) * factor) + "," +
            Math.round((n & 0xff) * factor) + ")";
    }

})();
