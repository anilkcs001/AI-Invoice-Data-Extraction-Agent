/**
 * @file app.js
 * @description Main graph logic — STATIC hierarchical layout (no rotation),
 * working filter pills, dark/light theme toggle.
 *
 * Layout: Top-to-bottom flowchart. Extensions with no dependencies at top,
 * deeper dependencies flow downward like a tree/org-chart.
 */
(function () {
    "use strict";

    // ═══════════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════════
    var network = null;
    var nodesDataset = null;
    var edgesDataset = null;
    var allNodes = [];
    var allEdges = [];
    var nodeMap = {};
    var depsOf = {};
    var requiredBy = {};
    var activeFilter = "all";
    var selectedNodeId = null;
    var isDarkMode = false;

    // ── Colors ──────────────────────────────────────────────────────
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
        ext: "Third Party"
    };
    var HIGHLIGHT_COLOR = "#f59e0b";

    // Theme-dependent colors — set by updateThemeColors()
    var COLORS = {};
    function updateThemeColors() {
        if (isDarkMode) {
            COLORS.bg = "#0f172a";
            COLORS.nodeFontColor = "#e2e8f0";
            COLORS.nodeFontStroke = "#0f172a";
            COLORS.edgeColor = "rgba(148,163,184,0.3)";
            COLORS.edgeDim = "rgba(148,163,184,0.08)";
            COLORS.dimNode = "rgba(255,255,255,0.08)";
            COLORS.dimFont = "rgba(255,255,255,0.2)";
        } else {
            COLORS.bg = "#ffffff";
            COLORS.nodeFontColor = "#1e293b";
            COLORS.nodeFontStroke = "#ffffff";
            COLORS.edgeColor = "rgba(100,116,139,0.35)";
            COLORS.edgeDim = "rgba(100,116,139,0.08)";
            COLORS.dimNode = "rgba(0,0,0,0.06)";
            COLORS.dimFont = "rgba(0,0,0,0.2)";
        }
    }
    updateThemeColors();

    // ═══════════════════════════════════════════════════════════════════
    // window.LoadGraph
    // ═══════════════════════════════════════════════════════════════════
    window.LoadGraph = function (jsonPayload) {
        var data;
        try {
            data = JSON.parse(jsonPayload);
        } catch (e) {
            showHint("Invalid JSON data received.");
            return;
        }
        if (!data || !data.nodes) {
            showHint("No extension data found.");
            return;
        }
        if (!data.edges) data.edges = [];

        allNodes = data.nodes;
        allEdges = data.edges;

        // Build lookups
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

        updateStats(allNodes.length, allEdges.length);
        activeFilter = "all";
        selectedNodeId = null;
        setActivePill("all");
        closeDetailPanel();
        rebuildGraph(allNodes, allEdges);
        hideHint();
    };

    // ═══════════════════════════════════════════════════════════════════
    // window.HighlightNode
    // ═══════════════════════════════════════════════════════════════════
    window.HighlightNode = function (appId) {
        if (!appId || !nodeMap[appId]) return;
        selectNode(appId);
    };

    // ═══════════════════════════════════════════════════════════════════
    // Graph rebuild — completely static hierarchical layout
    // ═══════════════════════════════════════════════════════════════════
    function rebuildGraph(nodes, edges) {
        var container = document.getElementById("dgNetwork");
        if (!container) return;

        if (network) {
            network.destroy();
            network = null;
        }

        var visNodes = [];
        for (var i = 0; i < nodes.length; i++) {
            visNodes.push(buildVisNode(nodes[i], false, false));
        }
        var visEdges = [];
        for (var j = 0; j < edges.length; j++) {
            visEdges.push(buildVisEdge(edges[j], j, false));
        }

        nodesDataset = new vis.DataSet(visNodes);
        edgesDataset = new vis.DataSet(visEdges);

        // ── STATIC hierarchical layout — NO physics, NO rotation ────
        var options = {
            autoResize: true,
            layout: {
                hierarchical: {
                    enabled: true,
                    direction: "UD",           // Up-to-Down (top = root, bottom = leaves)
                    sortMethod: "directed",    // Follow edge direction for ordering
                    levelSeparation: 120,      // Vertical gap between levels
                    nodeSpacing: 180,          // Horizontal gap between siblings
                    treeSpacing: 220,          // Gap between separate trees
                    blockShifting: true,
                    edgeMinimization: true,
                    parentCentralization: true,
                    shakeTowards: "roots"      // Push nodes with no incoming edges to top
                }
            },
            physics: {
                enabled: false               // *** COMPLETELY OFF — no movement, no rotation ***
            },
            interaction: {
                hover: true,
                tooltipDelay: 200,
                zoomView: true,
                dragView: true,
                dragNodes: true,             // User can manually drag nodes
                navigationButtons: false,
                keyboard: false
            },
            nodes: {
                shape: "box",                // Box shape — cleaner for flowcharts
                font: {
                    color: COLORS.nodeFontColor,
                    size: 12,
                    face: "'Inter', sans-serif",
                    multi: false
                },
                borderWidth: 2,
                borderWidthSelected: 3,
                margin: { top: 10, bottom: 10, left: 14, right: 14 },
                shadow: {
                    enabled: true,
                    color: "rgba(0,0,0,0.08)",
                    size: 6,
                    x: 0,
                    y: 2
                },
                widthConstraint: { minimum: 120, maximum: 240 }
            },
            edges: {
                arrows: { to: { enabled: true, scaleFactor: 0.7, type: "arrow" } },
                smooth: {
                    enabled: true,
                    type: "cubicBezier",
                    forceDirection: "vertical",
                    roundness: 0.4
                },
                width: 1.5,
                selectionWidth: 2.5
            }
        };

        network = new vis.Network(container, { nodes: nodesDataset, edges: edgesDataset }, options);

        // ── Click handler ───────────────────────────────────────────
        network.on("click", function (params) {
            if (params.nodes && params.nodes.length > 0) {
                selectNode(params.nodes[0]);
            } else {
                deselectAll();
                closeDetailPanel();
            }
        });

        network.on("hoverNode", function () { container.style.cursor = "pointer"; });
        network.on("blurNode", function () { container.style.cursor = "default"; });

        // Fit after layout settles
        setTimeout(function () {
            if (network) {
                network.fit({ animation: { duration: 400, easingFunction: "easeInOutQuad" } });
            }
        }, 300);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Node / Edge builders
    // ═══════════════════════════════════════════════════════════════════
    function buildVisNode(n, isSelected, isDimmed) {
        var baseColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;
        var bgColor, borderColor, fontColor;

        if (isSelected) {
            bgColor = HIGHLIGHT_COLOR;
            borderColor = "#d97706";
            fontColor = "#fff";
        } else if (isDimmed) {
            bgColor = COLORS.dimNode;
            borderColor = COLORS.dimNode;
            fontColor = COLORS.dimFont;
        } else {
            bgColor = isDarkMode ? darken(baseColor, 0.7) : lightenForBg(baseColor, 0.88);
            borderColor = baseColor;
            fontColor = COLORS.nodeFontColor;
        }

        var result = {
            id: n.id,
            label: truncate(n.name, 32),
            title: n.name + "\n" + n.publisher + "\nv" + n.version,
            color: {
                background: bgColor,
                border: borderColor,
                highlight: { background: HIGHLIGHT_COLOR, border: "#d97706" },
                hover: { background: lightenForBg(baseColor, isDarkMode ? 0.3 : 0.8), border: baseColor }
            },
            font: {
                color: fontColor,
                size: 12,
                face: "'Inter', sans-serif"
            },
            borderWidth: isSelected ? 3 : 2
        };

        if (isSelected) {
            result.shadow = { enabled: true, color: "rgba(245,158,11,0.35)", size: 14, x: 0, y: 0 };
        }

        return result;
    }

    function buildVisEdge(e, index, isDimmed) {
        return {
            id: "e" + index,
            from: e.from,
            to: e.to,
            arrows: "to",
            color: {
                color: isDimmed ? COLORS.edgeDim : COLORS.edgeColor,
                highlight: HIGHLIGHT_COLOR,
                hover: HIGHLIGHT_COLOR
            },
            width: isDimmed ? 0.5 : 1.5,
            smooth: { enabled: true, type: "cubicBezier", forceDirection: "vertical", roundness: 0.4 }
        };
    }

    // ═══════════════════════════════════════════════════════════════════
    // Selection
    // ═══════════════════════════════════════════════════════════════════
    function selectNode(nodeId) {
        if (!nodeMap[nodeId]) return;
        selectedNodeId = nodeId;
        var node = nodeMap[nodeId];

        var connectedIds = {};
        connectedIds[nodeId] = true;
        var deps = depsOf[nodeId] || [];
        var reqs = requiredBy[nodeId] || [];
        var i;
        for (i = 0; i < deps.length; i++) connectedIds[deps[i]] = true;
        for (i = 0; i < reqs.length; i++) connectedIds[reqs[i]] = true;

        // Update nodes
        var nodeUpdates = [];
        nodesDataset.forEach(function (vn) {
            var raw = nodeMap[vn.id];
            if (!raw) return;
            nodeUpdates.push(buildVisNode(raw, vn.id === nodeId, !connectedIds[vn.id]));
        });
        nodesDataset.update(nodeUpdates);

        // Update edges
        var edgeUpdates = [];
        edgesDataset.forEach(function (ve) {
            var both = connectedIds[ve.from] && connectedIds[ve.to];
            edgeUpdates.push({
                id: ve.id,
                color: {
                    color: both ? HIGHLIGHT_COLOR : COLORS.edgeDim,
                    highlight: HIGHLIGHT_COLOR,
                    hover: HIGHLIGHT_COLOR
                },
                width: both ? 2.5 : 0.5
            });
        });
        edgesDataset.update(edgeUpdates);

        // Focus
        if (network) {
            network.focus(nodeId, { scale: 1.0, animation: { duration: 400, easingFunction: "easeInOutQuad" } });
        }

        openDetailPanel(node);

        try {
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnNodeSelected", [
                node.id || "", node.name || "", node.publisher || "", node.version || ""
            ]);
        } catch (ex) { /* ignore */ }
    }

    function deselectAll() {
        selectedNodeId = null;
        if (!nodesDataset) return;

        var nodeUpdates = [];
        nodesDataset.forEach(function (vn) {
            var raw = nodeMap[vn.id];
            if (raw) nodeUpdates.push(buildVisNode(raw, false, false));
        });
        nodesDataset.update(nodeUpdates);

        var edgeUpdates = [];
        edgesDataset.forEach(function (ve) {
            edgeUpdates.push({
                id: ve.id,
                color: { color: COLORS.edgeColor, highlight: HIGHLIGHT_COLOR, hover: HIGHLIGHT_COLOR },
                width: 1.5
            });
        });
        edgesDataset.update(edgeUpdates);
    }

    // ═══════════════════════════════════════════════════════════════════
    // FILTERING — FIXED: completely rebuilds graph with filtered data
    // ═══════════════════════════════════════════════════════════════════
    function applyFilter(type) {
        activeFilter = type;
        selectedNodeId = null;
        closeDetailPanel();

        var filteredNodes = [];
        var visibleIds = {};
        var i;

        if (type === "all") {
            filteredNodes = allNodes.slice();
            for (i = 0; i < allNodes.length; i++) {
                visibleIds[allNodes[i].id] = true;
            }
        } else {
            for (i = 0; i < allNodes.length; i++) {
                if (allNodes[i].type === type) {
                    filteredNodes.push(allNodes[i]);
                    visibleIds[allNodes[i].id] = true;
                }
            }
        }

        var filteredEdges = [];
        for (i = 0; i < allEdges.length; i++) {
            if (visibleIds[allEdges[i].from] && visibleIds[allEdges[i].to]) {
                filteredEdges.push(allEdges[i]);
            }
        }

        updateStats(filteredNodes.length, filteredEdges.length);

        // FULL REBUILD — this is key. We destroy and recreate the network
        // so the hierarchical layout recalculates for the filtered subset.
        rebuildGraph(filteredNodes, filteredEdges);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Detail Panel
    // ═══════════════════════════════════════════════════════════════════
    function openDetailPanel(node) {
        var panel = document.getElementById("dgDetail");
        if (!panel) return;

        setTextById("dgDetailName", node.name || "Unknown");
        setTextById("dgDetailPublisher", node.publisher || "Unknown");
        setTextById("dgDetailVersion", "v" + (node.version || "0.0.0.0"));

        var typeEl = document.getElementById("dgDetailType");
        if (typeEl) {
            typeEl.textContent = TYPE_LABELS[node.type] || "Extension";
            typeEl.style.backgroundColor = TYPE_COLORS[node.type] || TYPE_COLORS.ext;
            typeEl.style.color = "#fff";
        }

        // Depends On
        var deps = (depsOf[node.id] || []).filter(function (id) { return !!nodeMap[id]; });
        setTextById("dgDepsCount", String(deps.length));
        var depsList = document.getElementById("dgDepsList");
        if (depsList) {
            depsList.innerHTML = "";
            if (deps.length === 0) {
                depsList.innerHTML = '<span class="dg-chip-empty">No dependencies</span>';
            } else {
                for (var d = 0; d < deps.length; d++) depsList.appendChild(createChip(deps[d]));
            }
        }

        // Required By
        var reqs = (requiredBy[node.id] || []).filter(function (id) { return !!nodeMap[id]; });
        setTextById("dgReqCount", String(reqs.length));
        var reqList = document.getElementById("dgReqList");
        if (reqList) {
            reqList.innerHTML = "";
            if (reqs.length === 0) {
                reqList.innerHTML = '<span class="dg-chip-empty">No dependents</span>';
            } else {
                for (var r = 0; r < reqs.length; r++) reqList.appendChild(createChip(reqs[r]));
            }
        }

        panel.classList.add("dg-detail-open");
    }

    function closeDetailPanel() {
        var panel = document.getElementById("dgDetail");
        if (panel) panel.classList.remove("dg-detail-open");
    }

    function createChip(nodeId) {
        var n = nodeMap[nodeId];
        if (!n) return document.createElement("span");

        var chip = document.createElement("button");
        chip.className = "dg-chip";
        chip.style.borderLeftColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;

        var dot = document.createElement("span");
        dot.className = "dg-chip-dot";
        dot.style.backgroundColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;
        chip.appendChild(dot);
        chip.appendChild(document.createTextNode(truncate(n.name, 34)));

        chip.addEventListener("click", function (evt) {
            evt.stopPropagation();
            // If node not visible due to filter, switch to All
            if (nodesDataset && !nodesDataset.get(nodeId)) {
                applyFilter("all");
                setActivePill("all");
                // Need a small delay for rebuild to finish
                setTimeout(function () { selectNode(nodeId); }, 400);
                return;
            }
            selectNode(nodeId);
        });

        return chip;
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

        updateThemeColors();

        // Re-render with current filter
        var currentNodes, currentEdges;
        if (activeFilter === "all") {
            currentNodes = allNodes;
            currentEdges = allEdges;
        } else {
            currentNodes = [];
            currentEdges = [];
            var visibleIds = {};
            for (var i = 0; i < allNodes.length; i++) {
                if (allNodes[i].type === activeFilter) {
                    currentNodes.push(allNodes[i]);
                    visibleIds[allNodes[i].id] = true;
                }
            }
            for (var j = 0; j < allEdges.length; j++) {
                if (visibleIds[allEdges[j].from] && visibleIds[allEdges[j].to]) {
                    currentEdges.push(allEdges[j]);
                }
            }
        }
        rebuildGraph(currentNodes, currentEdges);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Utilities
    // ═══════════════════════════════════════════════════════════════════
    function setTextById(id, text) {
        var el = document.getElementById(id);
        if (el) el.textContent = text;
    }

    function updateStats(nc, ec) {
        var sn = document.getElementById("dgStatNodesNum");
        var se = document.getElementById("dgStatEdgesNum");
        if (sn) sn.textContent = String(nc);
        if (se) se.textContent = String(ec);
    }

    function showHint(msg) {
        var h = document.getElementById("dgGraphHint");
        if (h) { h.textContent = msg; h.style.display = "flex"; }
    }

    function hideHint() {
        var h = document.getElementById("dgGraphHint");
        if (h) h.style.display = "none";
    }

    function truncate(str, max) {
        if (!str) return "";
        return str.length > max ? str.substring(0, max - 1) + "\u2026" : str;
    }

    /**
     * Creates a lighter version of a hex color for node backgrounds.
     * @param {string} hex - Base hex color
     * @param {number} factor - 0 to 1, higher = lighter
     * @returns {string} rgba color string
     */
    function lightenForBg(hex, factor) {
        if (!hex || hex.charAt(0) !== "#") return hex;
        var num = parseInt(hex.slice(1), 16);
        var r = (num >> 16) & 0xff;
        var g = (num >> 8) & 0xff;
        var b = num & 0xff;
        r = Math.round(r + (255 - r) * factor);
        g = Math.round(g + (255 - g) * factor);
        b = Math.round(b + (255 - b) * factor);
        return "rgb(" + r + "," + g + "," + b + ")";
    }

    /**
     * Darkens a hex color for dark-mode node backgrounds.
     * @param {string} hex
     * @param {number} factor - 0 to 1, lower = darker
     * @returns {string}
     */
    function darken(hex, factor) {
        if (!hex || hex.charAt(0) !== "#") return hex;
        var num = parseInt(hex.slice(1), 16);
        var r = Math.round(((num >> 16) & 0xff) * factor);
        var g = Math.round(((num >> 8) & 0xff) * factor);
        var b = Math.round((num & 0xff) * factor);
        return "rgb(" + r + "," + g + "," + b + ")";
    }

    function setActivePill(type) {
        var pills = document.querySelectorAll(".dg-pill");
        for (var i = 0; i < pills.length; i++) {
            var pill = pills[i];
            var pt = pill.getAttribute("data-type");
            if (pt === type) {
                pill.classList.add("dg-pill-active");
                if (pt !== "all" && TYPE_COLORS[pt]) {
                    pill.style.backgroundColor = TYPE_COLORS[pt];
                    pill.style.color = "#fff";
                    pill.style.borderColor = TYPE_COLORS[pt];
                } else {
                    pill.style.backgroundColor = "";
                    pill.style.color = "";
                    pill.style.borderColor = "";
                }
            } else {
                pill.classList.remove("dg-pill-active");
                pill.style.backgroundColor = "";
                pill.style.color = "";
                pill.style.borderColor = "";
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Event Wiring
    // ═══════════════════════════════════════════════════════════════════

    // ── Filter pills ────────────────────────────────────────────────
    var filtersEl = document.getElementById("dgFilters");
    if (filtersEl) {
        filtersEl.addEventListener("click", function (evt) {
            var target = evt.target;
            while (target && !target.classList.contains("dg-pill")) {
                if (target === filtersEl) { target = null; break; }
                target = target.parentElement;
            }
            if (!target) return;
            var type = target.getAttribute("data-type");
            if (!type) return;

            // Don't re-filter if already active
            if (type === activeFilter) return;

            setActivePill(type);
            applyFilter(type);
        });
    }

    // ── Detail close ────────────────────────────────────────────────
    var closeBtn = document.getElementById("dgDetailClose");
    if (closeBtn) {
        closeBtn.addEventListener("click", function (evt) {
            evt.stopPropagation();
            deselectAll();
            closeDetailPanel();
        });
    }

    // ── Theme toggle ────────────────────────────────────────────────
    var themeBtn = document.getElementById("dgThemeToggle");
    if (themeBtn) {
        themeBtn.addEventListener("click", function (evt) {
            evt.stopPropagation();
            toggleTheme();
        });
    }

    // ── Resize ──────────────────────────────────────────────────────
    window.addEventListener("resize", function () {
        if (network) setTimeout(function () { network.redraw(); }, 150);
    });

})();
