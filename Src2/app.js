/**
 * @file app.js
 * @description Main application logic for the Extension Dependency Graph.
 *
 * Exposes two window-level functions that BC calls via the control add-in:
 *   - window.LoadGraph(jsonPayload)  → parses JSON, renders vis.js network
 *   - window.HighlightNode(appId)    → programmatically selects a node
 *
 * Fires one callback to AL:
 *   - OnNodeSelected(AppId, AppName, Publisher, Version) via InvokeExtensibilityMethod
 *
 * Uses vis.js (loaded by startup.js from CDN). No build tools, no npm, no frameworks.
 */
(function () {
    "use strict";

    // ═══════════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════════

    /** @type {vis.Network|null} */
    var network = null;

    /** @type {vis.DataSet|null} */
    var nodesDataset = null;

    /** @type {vis.DataSet|null} */
    var edgesDataset = null;

    /** Full unfiltered data copies */
    var allNodes = [];
    var allEdges = [];

    /** Lookup maps built on data load */
    var nodeMap = {};       // id → node object
    var depsOf = {};        // id → [dependency ids]  (this node depends ON these)
    var requiredBy = {};    // id → [dependent ids]   (these nodes depend on THIS)

    /** Active UI state */
    var activeFilter = "all";
    var selectedNodeId = null;

    // ── Colour constants ────────────────────────────────────────────
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
    var DIM_COLOR = "rgba(255,255,255,0.06)";
    var DIM_EDGE_COLOR = "rgba(255,255,255,0.04)";
    var EDGE_DEFAULT_COLOR = "rgba(255,255,255,0.18)";

    // ═══════════════════════════════════════════════════════════════════
    // window.LoadGraph — called by AL via CurrPage.GraphControl.LoadGraph()
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Parses the JSON payload from AL and renders the vis.js network graph.
     * @param {string} jsonPayload - JSON string: { "nodes": [...], "edges": [...] }
     */
    window.LoadGraph = function (jsonPayload) {
        var data;
        try {
            data = JSON.parse(jsonPayload);
        } catch (e) {
            console.error("LoadGraph: invalid JSON", e);
            showHint("Invalid graph data received.");
            return;
        }

        if (!data || !data.nodes) {
            showHint("Graph data is empty or missing nodes array.");
            return;
        }

        // Default edges to empty array if not present (no dependencies found)
        if (!data.edges) {
            data.edges = [];
        }

        // ── Store raw data ──────────────────────────────────────────
        allNodes = data.nodes;
        allEdges = data.edges;

        // ── Build lookup maps ───────────────────────────────────────
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
            // edge.from DEPENDS ON edge.to
            if (depsOf[e.from]) {
                depsOf[e.from].push(e.to);
            }
            if (requiredBy[e.to]) {
                requiredBy[e.to].push(e.from);
            }
        }

        // ── Update stats bar ────────────────────────────────────────
        updateStats(allNodes.length, allEdges.length);

        // ── Build vis.js DataSets ───────────────────────────────────
        var visNodes = [];
        for (i = 0; i < allNodes.length; i++) {
            visNodes.push(buildVisNode(allNodes[i], false, false));
        }

        var visEdges = [];
        for (i = 0; i < allEdges.length; i++) {
            visEdges.push(buildVisEdge(allEdges[i], i, false));
        }

        nodesDataset = new vis.DataSet(visNodes);
        edgesDataset = new vis.DataSet(visEdges);

        renderNetwork();
        hideHint();

        // Reset UI state
        activeFilter = "all";
        selectedNodeId = null;
        setActivePill("all");
        closeDetailPanel();
    };

    // ═══════════════════════════════════════════════════════════════════
    // window.HighlightNode — called by AL
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Programmatically selects and highlights a node by its App ID.
     * @param {string} appId - The GUID of the extension to highlight.
     */
    window.HighlightNode = function (appId) {
        if (!appId || !nodeMap[appId]) return;
        selectNode(appId);
    };

    // ═══════════════════════════════════════════════════════════════════
    // Network rendering
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Creates or recreates the vis.js Network instance.
     */
    function renderNetwork() {
        var container = document.getElementById("dgNetwork");
        if (!container) return;

        if (network) {
            network.destroy();
            network = null;
        }

        var options = {
            autoResize: true,
            physics: {
                enabled: true,
                solver: "forceAtlas2Based",
                forceAtlas2Based: {
                    gravitationalConstant: -45,
                    centralGravity: 0.008,
                    springLength: 150,
                    springConstant: 0.04,
                    damping: 0.4,
                    avoidOverlap: 0.65
                },
                stabilization: {
                    enabled: true,
                    iterations: 200,
                    updateInterval: 25
                }
            },
            interaction: {
                hover: true,
                tooltipDelay: 250,
                zoomView: true,
                dragView: true,
                navigationButtons: false,
                keyboard: false
            },
            nodes: {
                shape: "dot",
                font: {
                    color: "#e2e8f0",
                    size: 11,
                    face: "'DM Sans', sans-serif",
                    strokeWidth: 2,
                    strokeColor: "#070b12"
                },
                borderWidth: 2,
                borderWidthSelected: 3,
                shadow: {
                    enabled: true,
                    color: "rgba(0,0,0,0.3)",
                    size: 8,
                    x: 0,
                    y: 2
                }
            },
            edges: {
                arrows: { to: { enabled: true, scaleFactor: 0.6 } },
                smooth: { type: "continuous", roundness: 0.35 },
                width: 1
            }
        };

        network = new vis.Network(
            container,
            { nodes: nodesDataset, edges: edgesDataset },
            options
        );

        // ── Click handler ───────────────────────────────────────────
        network.on("click", function (params) {
            if (params.nodes && params.nodes.length > 0) {
                selectNode(params.nodes[0]);
            } else {
                deselectAll();
                closeDetailPanel();
            }
        });

        // ── Hover cursor ────────────────────────────────────────────
        network.on("hoverNode", function () {
            container.style.cursor = "pointer";
        });
        network.on("blurNode", function () {
            container.style.cursor = "default";
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // Node / Edge builders
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Builds a vis.js node options object from raw node data.
     * @param {Object} n - { id, name, publisher, version, type }
     * @param {boolean} isSelected - Is this the currently selected node?
     * @param {boolean} isDimmed - Should this node be dimmed?
     * @returns {Object} vis.js node definition
     */
    function buildVisNode(n, isSelected, isDimmed) {
        var baseColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;
        var bgColor, borderColor, fontColor, nodeSize;

        if (isSelected) {
            bgColor = HIGHLIGHT_COLOR;
            borderColor = "#fbbf24";
            fontColor = "#fef3c7";
            nodeSize = 22;
        } else if (isDimmed) {
            bgColor = DIM_COLOR;
            borderColor = DIM_COLOR;
            fontColor = "rgba(255,255,255,0.15)";
            nodeSize = 10;
        } else {
            bgColor = baseColor;
            borderColor = lightenHex(baseColor, 30);
            fontColor = "#e2e8f0";
            nodeSize = 14;
        }

        var result = {
            id: n.id,
            label: truncate(n.name, 24),
            title: n.name + "\n" + n.publisher + "\nv" + n.version,
            size: nodeSize,
            color: {
                background: bgColor,
                border: borderColor,
                highlight: { background: HIGHLIGHT_COLOR, border: "#fbbf24" },
                hover: { background: lightenHex(baseColor, 20), border: lightenHex(baseColor, 40) }
            },
            font: { color: fontColor }
        };

        if (isSelected) {
            result.shadow = {
                enabled: true,
                color: HIGHLIGHT_COLOR,
                size: 20,
                x: 0,
                y: 0
            };
        }

        return result;
    }

    /**
     * Builds a vis.js edge options object.
     * @param {Object} e - { from, to }
     * @param {number} index - Edge index for unique ID
     * @param {boolean} isDimmed - Whether edge should be dimmed
     * @returns {Object}
     */
    function buildVisEdge(e, index, isDimmed) {
        return {
            id: "e" + index,
            from: e.from,
            to: e.to,
            arrows: "to",
            color: {
                color: isDimmed ? DIM_EDGE_COLOR : EDGE_DEFAULT_COLOR,
                highlight: HIGHLIGHT_COLOR,
                hover: HIGHLIGHT_COLOR
            },
            width: isDimmed ? 0.5 : 1,
            smooth: { type: "continuous", roundness: 0.35 }
        };
    }

    // ═══════════════════════════════════════════════════════════════════
    // Selection & highlighting
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Selects a node: highlights it + direct connections, dims everything else,
     * opens detail panel, fires OnNodeSelected callback to AL.
     * @param {string} nodeId
     */
    function selectNode(nodeId) {
        if (!nodeMap[nodeId]) return;

        selectedNodeId = nodeId;
        var node = nodeMap[nodeId];

        // Build set of connected node IDs (self + direct deps + direct dependents)
        var connectedIds = {};
        connectedIds[nodeId] = true;

        var deps = depsOf[nodeId] || [];
        var reqs = requiredBy[nodeId] || [];
        var i;

        for (i = 0; i < deps.length; i++) {
            connectedIds[deps[i]] = true;
        }
        for (i = 0; i < reqs.length; i++) {
            connectedIds[reqs[i]] = true;
        }

        // Update node visuals
        var nodeUpdates = [];
        nodesDataset.forEach(function (visNode) {
            var raw = nodeMap[visNode.id];
            if (!raw) return;
            var isSel = (visNode.id === nodeId);
            var isConn = !!connectedIds[visNode.id];
            nodeUpdates.push(buildVisNode(raw, isSel, !isConn));
        });
        nodesDataset.update(nodeUpdates);

        // Update edge visuals
        var edgeUpdates = [];
        edgesDataset.forEach(function (visEdge) {
            var bothConnected = connectedIds[visEdge.from] && connectedIds[visEdge.to];
            edgeUpdates.push({
                id: visEdge.id,
                color: {
                    color: bothConnected ? HIGHLIGHT_COLOR : DIM_EDGE_COLOR,
                    highlight: HIGHLIGHT_COLOR,
                    hover: HIGHLIGHT_COLOR
                },
                width: bothConnected ? 2 : 0.5
            });
        });
        edgesDataset.update(edgeUpdates);

        // Focus camera on selected node
        if (network) {
            network.focus(nodeId, {
                scale: 1.1,
                animation: { duration: 500, easingFunction: "easeInOutCubic" }
            });
        }

        // Show detail panel
        openDetailPanel(node);

        // Fire callback to AL
        try {
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnNodeSelected", [
                node.id || "",
                node.name || "",
                node.publisher || "",
                node.version || ""
            ]);
        } catch (ex) {
            console.warn("OnNodeSelected callback failed:", ex);
        }
    }

    /**
     * Deselects all: restores default node/edge appearance for current filter.
     */
    function deselectAll() {
        selectedNodeId = null;

        var nodeUpdates = [];
        nodesDataset.forEach(function (visNode) {
            var raw = nodeMap[visNode.id];
            if (raw) {
                nodeUpdates.push(buildVisNode(raw, false, false));
            }
        });
        nodesDataset.update(nodeUpdates);

        var edgeUpdates = [];
        edgesDataset.forEach(function (visEdge) {
            edgeUpdates.push({
                id: visEdge.id,
                color: {
                    color: EDGE_DEFAULT_COLOR,
                    highlight: HIGHLIGHT_COLOR,
                    hover: HIGHLIGHT_COLOR
                },
                width: 1
            });
        });
        edgesDataset.update(edgeUpdates);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Filtering
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Applies a type filter. Shows only nodes of the given type and
     * edges where both endpoints are visible.
     * @param {string} type - 'all', 'ms', 'isv', 'custom', 'ext'
     */
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

        // Rebuild datasets
        var visNodes = [];
        for (i = 0; i < filteredNodes.length; i++) {
            visNodes.push(buildVisNode(filteredNodes[i], false, false));
        }
        var visEdges = [];
        for (i = 0; i < filteredEdges.length; i++) {
            visEdges.push(buildVisEdge(filteredEdges[i], i, false));
        }

        nodesDataset.clear();
        edgesDataset.clear();
        nodesDataset.add(visNodes);
        edgesDataset.add(visEdges);

        updateStats(filteredNodes.length, filteredEdges.length);

        if (network) {
            setTimeout(function () {
                network.fit({
                    animation: { duration: 600, easingFunction: "easeInOutCubic" }
                });
            }, 100);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Detail Panel
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Opens and populates the detail panel with data for the given node.
     * @param {Object} node - { id, name, publisher, version, type }
     */
    function openDetailPanel(node) {
        var panel = document.getElementById("dgDetail");
        if (!panel) return;

        // Name
        setTextById("dgDetailName", node.name || "Unknown");

        // Publisher + Version
        setTextById("dgDetailPublisher", node.publisher || "Unknown");
        setTextById("dgDetailVersion", "v" + (node.version || "0.0.0.0"));

        // Type badge
        var typeEl = document.getElementById("dgDetailType");
        if (typeEl) {
            typeEl.textContent = TYPE_LABELS[node.type] || "Extension";
            typeEl.style.backgroundColor = TYPE_COLORS[node.type] || TYPE_COLORS.ext;
        }

        // ── Depends On section ──────────────────────────────────────
        var deps = (depsOf[node.id] || []).filter(function (id) {
            return !!nodeMap[id];
        });
        setTextById("dgDepsCount", String(deps.length));
        var depsList = document.getElementById("dgDepsList");
        if (depsList) {
            depsList.innerHTML = "";
            if (deps.length === 0) {
                depsList.innerHTML = '<span class="dg-chip-empty">No dependencies</span>';
            } else {
                for (var d = 0; d < deps.length; d++) {
                    depsList.appendChild(createChip(deps[d]));
                }
            }
        }

        // ── Required By section ─────────────────────────────────────
        var reqs = (requiredBy[node.id] || []).filter(function (id) {
            return !!nodeMap[id];
        });
        setTextById("dgReqCount", String(reqs.length));
        var reqList = document.getElementById("dgReqList");
        if (reqList) {
            reqList.innerHTML = "";
            if (reqs.length === 0) {
                reqList.innerHTML = '<span class="dg-chip-empty">No dependents</span>';
            } else {
                for (var r = 0; r < reqs.length; r++) {
                    reqList.appendChild(createChip(reqs[r]));
                }
            }
        }

        // Slide panel in
        panel.classList.add("dg-detail-open");
    }

    /**
     * Closes / hides the detail panel with slide-out animation.
     */
    function closeDetailPanel() {
        var panel = document.getElementById("dgDetail");
        if (panel) {
            panel.classList.remove("dg-detail-open");
        }
    }

    /**
     * Creates a clickable chip element for a dependency or dependent.
     * Clicking a chip selects that node in the graph.
     * @param {string} nodeId - App ID of the chip target
     * @returns {HTMLElement}
     */
    function createChip(nodeId) {
        var n = nodeMap[nodeId];
        if (!n) return document.createElement("span");

        var chip = document.createElement("button");
        chip.className = "dg-chip";
        chip.style.borderColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;

        var dot = document.createElement("span");
        dot.className = "dg-chip-dot";
        dot.style.backgroundColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;

        chip.appendChild(dot);
        chip.appendChild(document.createTextNode(truncate(n.name, 30)));

        chip.addEventListener("click", function (evt) {
            evt.stopPropagation();
            // If the node is hidden by current filter, reset to All first
            if (nodesDataset && !nodesDataset.get(nodeId)) {
                applyFilter("all");
                setActivePill("all");
            }
            selectNode(nodeId);
        });

        return chip;
    }

    // ═══════════════════════════════════════════════════════════════════
    // Utility functions
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Sets textContent of an element by its ID.
     * @param {string} elId
     * @param {string} text
     */
    function setTextById(elId, text) {
        var el = document.getElementById(elId);
        if (el) el.textContent = text;
    }

    /**
     * Updates the stats display in the top bar.
     * @param {number} nodeCount
     * @param {number} edgeCount
     */
    function updateStats(nodeCount, edgeCount) {
        var sn = document.querySelector("#dgStatNodes .dg-stat-num");
        var se = document.querySelector("#dgStatEdges .dg-stat-num");
        if (sn) sn.textContent = String(nodeCount);
        if (se) se.textContent = String(edgeCount);
    }

    /**
     * Shows the loading/hint overlay on the graph area.
     * @param {string} msg
     */
    function showHint(msg) {
        var h = document.getElementById("dgGraphHint");
        if (h) {
            h.textContent = msg;
            h.style.display = "flex";
        }
    }

    /**
     * Hides the loading/hint overlay.
     */
    function hideHint() {
        var h = document.getElementById("dgGraphHint");
        if (h) h.style.display = "none";
    }

    /**
     * Truncates a string and appends ellipsis if needed.
     * @param {string} str
     * @param {number} max
     * @returns {string}
     */
    function truncate(str, max) {
        if (!str) return "";
        return str.length > max ? str.substring(0, max - 1) + "\u2026" : str;
    }

    /**
     * Lightens a hex colour by adding to each RGB channel.
     * @param {string} hex - "#rrggbb" format
     * @param {number} amount - Value to add per channel (0-255)
     * @returns {string} Lightened hex colour
     */
    function lightenHex(hex, amount) {
        if (!hex || hex.charAt(0) !== "#" || hex.length < 7) return hex;
        var num = parseInt(hex.slice(1), 16);
        var r = Math.min(255, (num >> 16) + amount);
        var g = Math.min(255, ((num >> 8) & 0xff) + amount);
        var b = Math.min(255, (num & 0xff) + amount);
        return "#" + ((1 << 24) | (r << 16) | (g << 8) | b).toString(16).slice(1);
    }

    /**
     * Sets the active filter pill styling. The active pill gets a coloured
     * background matching its type and a glow box-shadow.
     * @param {string} type - The type to make active
     */
    function setActivePill(type) {
        var pills = document.querySelectorAll(".dg-pill");
        for (var i = 0; i < pills.length; i++) {
            var pill = pills[i];
            var pillType = pill.getAttribute("data-type");
            if (pillType === type) {
                pill.classList.add("dg-pill-active");
                if (pillType !== "all" && TYPE_COLORS[pillType]) {
                    pill.style.backgroundColor = TYPE_COLORS[pillType];
                    pill.style.boxShadow = "0 0 12px " + TYPE_COLORS[pillType];
                    pill.style.borderColor = TYPE_COLORS[pillType];
                    pill.style.color = "#fff";
                } else {
                    pill.style.backgroundColor = "";
                    pill.style.boxShadow = "";
                    pill.style.borderColor = "";
                    pill.style.color = "";
                }
            } else {
                pill.classList.remove("dg-pill-active");
                pill.style.backgroundColor = "";
                pill.style.boxShadow = "";
                pill.style.borderColor = "";
                pill.style.color = "";
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Event wiring (runs once when this script file is loaded)
    // ═══════════════════════════════════════════════════════════════════

    // ── Filter pills click delegation ───────────────────────────────
    var filtersEl = document.getElementById("dgFilters");
    if (filtersEl) {
        filtersEl.addEventListener("click", function (evt) {
            var target = evt.target;
            // Walk up to find the pill button
            while (target && !target.classList.contains("dg-pill")) {
                target = target.parentElement;
                if (target === filtersEl) { target = null; break; }
            }
            if (!target) return;

            var type = target.getAttribute("data-type");
            if (!type) return;

            setActivePill(type);
            applyFilter(type);
        });
    }

    // ── Detail panel close button ───────────────────────────────────
    var closeBtn = document.getElementById("dgDetailClose");
    if (closeBtn) {
        closeBtn.addEventListener("click", function (evt) {
            evt.stopPropagation();
            deselectAll();
            closeDetailPanel();
        });
    }

    // ── Window resize handler ───────────────────────────────────────
    window.addEventListener("resize", function () {
        if (network) {
            setTimeout(function () {
                network.redraw();
            }, 150);
        }
    });

})();
