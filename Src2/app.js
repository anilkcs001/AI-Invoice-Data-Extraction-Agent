/**
 * @file app.js
 * @description Main application logic for the Extension Dependency Graph control add-in.
 *
 * Exposes two window-level functions consumed by the AL control add-in:
 *   - LoadGraph(jsonPayload)   – parses JSON and renders the vis.js network
 *   - HighlightNode(appId)     – programmatically selects and highlights a node
 *
 * All interaction (filtering, detail panel, click handling) is managed here.
 */

(function () {
    "use strict";

    // ═══════════════════════════════════════════════════════════════════
    // Module-level state
    // ═══════════════════════════════════════════════════════════════════

    /** @type {vis.Network|null} */
    var network = null;

    /** @type {vis.DataSet} */
    var nodesDataset = null;

    /** @type {vis.DataSet} */
    var edgesDataset = null;

    /** Full unfiltered copies for reset */
    var allNodes = [];
    var allEdges = [];

    /** Lookup maps */
    var nodeMap = {};        // id → node object {id, name, publisher, version, type}
    var depsOf = {};         // id → [dependency ids]
    var requiredBy = {};     // id → [ids that depend on this]

    /** Current active filter type */
    var activeFilter = "all";

    /** Currently selected node id */
    var selectedNodeId = null;

    // ── Color constants ─────────────────────────────────────────────────
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
    // LoadGraph – called from AL via CurrPage.GraphControl.LoadGraph()
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Parses the JSON payload from AL and renders the vis.js network graph.
     * @param {string} jsonPayload - Serialised JSON with { nodes: [], edges: [] }
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

        if (!data.nodes || !data.edges) {
            showHint("Graph data is missing nodes or edges.");
            return;
        }

        // ── Store raw data ──────────────────────────────────────────────
        allNodes = data.nodes || [];
        allEdges = data.edges || [];

        // Build lookup maps
        nodeMap = {};
        depsOf = {};
        requiredBy = {};

        allNodes.forEach(function (n) {
            nodeMap[n.id] = n;
            depsOf[n.id] = [];
            requiredBy[n.id] = [];
        });

        allEdges.forEach(function (e) {
            // e.from depends on e.to
            if (depsOf[e.from]) depsOf[e.from].push(e.to);
            if (requiredBy[e.to]) requiredBy[e.to].push(e.from);
        });

        // ── Update stats ────────────────────────────────────────────────
        updateStats(allNodes.length, allEdges.length);

        // ── Build vis datasets ──────────────────────────────────────────
        var visNodes = allNodes.map(function (n) {
            return buildVisNode(n, false, false);
        });

        var visEdges = allEdges.map(function (e, i) {
            return {
                id: "e" + i,
                from: e.from,
                to: e.to,
                arrows: "to",
                color: { color: EDGE_DEFAULT_COLOR, highlight: HIGHLIGHT_COLOR, hover: HIGHLIGHT_COLOR },
                width: 1,
                smooth: { type: "continuous", roundness: 0.35 }
            };
        });

        nodesDataset = new vis.DataSet(visNodes);
        edgesDataset = new vis.DataSet(visEdges);

        renderNetwork();
        hideHint();

        // Reset UI state
        activeFilter = "all";
        setActivePill("all");
        closeDetailPanel();
    };

    // ═══════════════════════════════════════════════════════════════════
    // HighlightNode – called from AL via CurrPage.GraphControl.HighlightNode()
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
    // Internal: Network rendering
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Creates / recreates the vis.js Network instance.
     */
    function renderNetwork() {
        var container = document.getElementById("dgNetwork");
        if (!container) return;

        // Destroy previous instance
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
                    gravitationalConstant: -40,
                    centralGravity: 0.008,
                    springLength: 160,
                    springConstant: 0.04,
                    damping: 0.4,
                    avoidOverlap: 0.6
                },
                stabilization: {
                    enabled: true,
                    iterations: 200,
                    updateInterval: 25
                }
            },
            interaction: {
                hover: true,
                tooltipDelay: 200,
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

        network = new vis.Network(container, { nodes: nodesDataset, edges: edgesDataset }, options);

        // ── Click handler ───────────────────────────────────────────────
        network.on("click", function (params) {
            if (params.nodes && params.nodes.length > 0) {
                var clickedId = params.nodes[0];
                selectNode(clickedId);
            } else {
                // Clicked empty space → deselect
                deselectAll();
                closeDetailPanel();
            }
        });

        // ── Hover cursor ────────────────────────────────────────────────
        network.on("hoverNode", function () {
            container.style.cursor = "pointer";
        });
        network.on("blurNode", function () {
            container.style.cursor = "default";
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // Internal: Node building helpers
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Builds a vis.js node options object.
     * @param {Object} n       - Raw node { id, name, publisher, version, type }
     * @param {boolean} highlight - Whether this node is highlighted (selected)
     * @param {boolean} dim       - Whether this node should be dimmed
     * @returns {Object} vis.js node definition
     */
    function buildVisNode(n, highlight, dim) {
        var baseColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;
        var color, fontColor, size, borderColor;

        if (highlight) {
            color = HIGHLIGHT_COLOR;
            borderColor = "#fbbf24";
            fontColor = "#fef3c7";
            size = 22;
        } else if (dim) {
            color = DIM_COLOR;
            borderColor = DIM_COLOR;
            fontColor = "rgba(255,255,255,0.15)";
            size = 10;
        } else {
            color = baseColor;
            borderColor = lighten(baseColor, 30);
            fontColor = "#e2e8f0";
            size = 14;
        }

        return {
            id: n.id,
            label: truncateLabel(n.name, 24),
            title: n.name + "\n" + n.publisher + "\nv" + n.version,
            size: size,
            color: {
                background: color,
                border: borderColor,
                highlight: { background: HIGHLIGHT_COLOR, border: "#fbbf24" },
                hover: { background: lighten(baseColor, 20), border: lighten(baseColor, 40) }
            },
            font: { color: fontColor },
            shadow: highlight ? { enabled: true, color: HIGHLIGHT_COLOR, size: 18, x: 0, y: 0 } : undefined
        };
    }

    /**
     * Truncates a label string and appends ellipsis if too long.
     * @param {string} str
     * @param {number} max
     * @returns {string}
     */
    function truncateLabel(str, max) {
        if (!str) return "";
        return str.length > max ? str.substring(0, max - 1) + "…" : str;
    }

    /**
     * Naive colour lightening by a percentage-ish amount.
     * @param {string} hex - 7-char hex colour
     * @param {number} amount - 0-255 additive amount per channel
     * @returns {string} hex colour
     */
    function lighten(hex, amount) {
        if (!hex || hex.charAt(0) !== "#") return hex;
        var num = parseInt(hex.slice(1), 16);
        var r = Math.min(255, (num >> 16) + amount);
        var g = Math.min(255, ((num >> 8) & 0x00ff) + amount);
        var b = Math.min(255, (num & 0x0000ff) + amount);
        return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Internal: Selection & highlighting
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Selects a node: highlights it and its direct connections, dims everything else,
     * opens the detail panel, and fires the OnNodeSelected callback to AL.
     * @param {string} nodeId
     */
    function selectNode(nodeId) {
        if (!nodeMap[nodeId]) return;

        selectedNodeId = nodeId;
        var node = nodeMap[nodeId];

        // Determine connected node ids (direct neighbours)
        var connectedIds = {};
        connectedIds[nodeId] = true;
        (depsOf[nodeId] || []).forEach(function (id) { connectedIds[id] = true; });
        (requiredBy[nodeId] || []).forEach(function (id) { connectedIds[id] = true; });

        // Update all node visuals
        var updates = [];
        allNodes.forEach(function (n) {
            // Only update nodes currently in the dataset (respecting filters)
            if (!nodesDataset.get(n.id)) return;
            var isSelected = (n.id === nodeId);
            var isConnected = !!connectedIds[n.id];
            updates.push(buildVisNode(n, isSelected, !isConnected));
        });
        nodesDataset.update(updates);

        // Update edge visuals
        var edgeUpdates = [];
        edgesDataset.forEach(function (e) {
            var connected = (connectedIds[e.from] && connectedIds[e.to]);
            edgeUpdates.push({
                id: e.id,
                color: {
                    color: connected ? HIGHLIGHT_COLOR : DIM_EDGE_COLOR,
                    highlight: HIGHLIGHT_COLOR,
                    hover: HIGHLIGHT_COLOR
                },
                width: connected ? 2 : 0.5
            });
        });
        edgesDataset.update(edgeUpdates);

        // Focus camera
        if (network) {
            network.focus(nodeId, { scale: 1.1, animation: { duration: 500, easingFunction: "easeInOutCubic" } });
        }

        // Open detail panel
        openDetailPanel(node);

        // Fire callback to AL
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnNodeSelected", [
            node.id,
            node.name,
            node.publisher,
            node.version
        ]);
    }

    /**
     * Deselects all nodes, restoring default colours based on current filter.
     */
    function deselectAll() {
        selectedNodeId = null;

        var updates = [];
        nodesDataset.forEach(function (visNode) {
            var n = nodeMap[visNode.id];
            if (n) updates.push(buildVisNode(n, false, false));
        });
        nodesDataset.update(updates);

        var edgeUpdates = [];
        edgesDataset.forEach(function (e) {
            edgeUpdates.push({
                id: e.id,
                color: { color: EDGE_DEFAULT_COLOR, highlight: HIGHLIGHT_COLOR, hover: HIGHLIGHT_COLOR },
                width: 1
            });
        });
        edgesDataset.update(edgeUpdates);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Internal: Filtering
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Applies a type filter. Shows only nodes of the specified type (or all).
     * Edges are shown only if both endpoints are visible.
     * @param {string} type - 'all', 'ms', 'isv', 'custom', 'ext'
     */
    function applyFilter(type) {
        activeFilter = type;
        selectedNodeId = null;
        closeDetailPanel();

        var filteredNodes, filteredEdges;
        var visibleIds = {};

        if (type === "all") {
            filteredNodes = allNodes;
            allNodes.forEach(function (n) { visibleIds[n.id] = true; });
        } else {
            filteredNodes = allNodes.filter(function (n) { return n.type === type; });
            filteredNodes.forEach(function (n) { visibleIds[n.id] = true; });
        }

        filteredEdges = allEdges.filter(function (e) {
            return visibleIds[e.from] && visibleIds[e.to];
        });

        // Rebuild datasets
        var visNodes = filteredNodes.map(function (n) {
            return buildVisNode(n, false, false);
        });
        var visEdges = filteredEdges.map(function (e, i) {
            return {
                id: "e" + i,
                from: e.from,
                to: e.to,
                arrows: "to",
                color: { color: EDGE_DEFAULT_COLOR, highlight: HIGHLIGHT_COLOR, hover: HIGHLIGHT_COLOR },
                width: 1,
                smooth: { type: "continuous", roundness: 0.35 }
            };
        });

        nodesDataset.clear();
        edgesDataset.clear();
        nodesDataset.add(visNodes);
        edgesDataset.add(visEdges);

        // Update stats for visible items
        updateStats(filteredNodes.length, filteredEdges.length);

        // Re-fit the view after filter
        if (network) {
            setTimeout(function () {
                network.fit({ animation: { duration: 600, easingFunction: "easeInOutCubic" } });
            }, 100);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Internal: Detail Panel
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Opens the detail panel and populates it with the given node's data.
     * @param {Object} node - { id, name, publisher, version, type }
     */
    function openDetailPanel(node) {
        var panel = document.getElementById("dgDetail");
        if (!panel) return;

        // Name
        setText("dgDetailName", node.name);

        // Publisher + Version badges
        setText("dgDetailPublisher", node.publisher);
        setText("dgDetailVersion", "v" + node.version);

        // Type badge
        var typeEl = document.getElementById("dgDetailType");
        if (typeEl) {
            typeEl.textContent = TYPE_LABELS[node.type] || "Extension";
            typeEl.style.backgroundColor = TYPE_COLORS[node.type] || TYPE_COLORS.ext;
        }

        // Depends On
        var deps = (depsOf[node.id] || []).filter(function (id) { return !!nodeMap[id]; });
        var depsList = document.getElementById("dgDepsList");
        var depsCount = document.getElementById("dgDepsCount");
        if (depsCount) depsCount.textContent = deps.length;
        if (depsList) {
            depsList.innerHTML = "";
            if (deps.length === 0) {
                depsList.innerHTML = '<span class="dg-chip-empty">No dependencies</span>';
            } else {
                deps.forEach(function (depId) {
                    depsList.appendChild(createChip(depId));
                });
            }
        }

        // Required By
        var reqs = (requiredBy[node.id] || []).filter(function (id) { return !!nodeMap[id]; });
        var reqList = document.getElementById("dgReqList");
        var reqCount = document.getElementById("dgReqCount");
        if (reqCount) reqCount.textContent = reqs.length;
        if (reqList) {
            reqList.innerHTML = "";
            if (reqs.length === 0) {
                reqList.innerHTML = '<span class="dg-chip-empty">No dependents</span>';
            } else {
                reqs.forEach(function (reqId) {
                    reqList.appendChild(createChip(reqId));
                });
            }
        }

        // Slide panel in
        panel.classList.add("dg-detail-open");
    }

    /**
     * Closes the detail panel.
     */
    function closeDetailPanel() {
        var panel = document.getElementById("dgDetail");
        if (panel) panel.classList.remove("dg-detail-open");
    }

    /**
     * Creates a clickable chip element for a dependency / dependent.
     * @param {string} nodeId
     * @returns {HTMLElement}
     */
    function createChip(nodeId) {
        var n = nodeMap[nodeId];
        var chip = document.createElement("button");
        chip.className = "dg-chip";
        chip.style.borderColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;

        var dot = document.createElement("span");
        dot.className = "dg-chip-dot";
        dot.style.backgroundColor = TYPE_COLORS[n.type] || TYPE_COLORS.ext;

        chip.appendChild(dot);
        chip.appendChild(document.createTextNode(truncateLabel(n.name, 30)));

        chip.addEventListener("click", function (e) {
            e.stopPropagation();
            // If the node isn't visible (due to filter), switch filter to All first
            if (!nodesDataset.get(nodeId)) {
                applyFilter("all");
                setActivePill("all");
            }
            selectNode(nodeId);
        });

        return chip;
    }

    // ═══════════════════════════════════════════════════════════════════
    // Internal: UI helpers
    // ═══════════════════════════════════════════════════════════════════

    function setText(elId, text) {
        var el = document.getElementById(elId);
        if (el) el.textContent = text || "—";
    }

    function updateStats(nodeCount, edgeCount) {
        var sn = document.querySelector("#dgStatNodes .dg-stat-num");
        var se = document.querySelector("#dgStatEdges .dg-stat-num");
        if (sn) sn.textContent = nodeCount;
        if (se) se.textContent = edgeCount;
    }

    function showHint(msg) {
        var h = document.getElementById("dgGraphHint");
        if (h) {
            h.textContent = msg;
            h.style.display = "flex";
        }
    }

    function hideHint() {
        var h = document.getElementById("dgGraphHint");
        if (h) h.style.display = "none";
    }

    /**
     * Sets the active pill styling.
     * @param {string} type
     */
    function setActivePill(type) {
        var pills = document.querySelectorAll(".dg-pill");
        pills.forEach(function (pill) {
            var pillType = pill.getAttribute("data-type");
            if (pillType === type) {
                pill.classList.add("dg-pill-active");
                if (pillType !== "all") {
                    pill.style.backgroundColor = TYPE_COLORS[pillType] || "";
                    pill.style.boxShadow = "0 0 12px " + (TYPE_COLORS[pillType] || "transparent");
                } else {
                    pill.style.backgroundColor = "";
                    pill.style.boxShadow = "";
                }
            } else {
                pill.classList.remove("dg-pill-active");
                pill.style.backgroundColor = "";
                pill.style.boxShadow = "";
            }
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // Event wiring (runs once on script load)
    // ═══════════════════════════════════════════════════════════════════

    // Filter pills click delegation
    var filtersContainer = document.getElementById("dgFilters");
    if (filtersContainer) {
        filtersContainer.addEventListener("click", function (e) {
            var pill = e.target.closest(".dg-pill");
            if (!pill) return;
            var type = pill.getAttribute("data-type");
            if (!type) return;
            setActivePill(type);
            applyFilter(type);
        });
    }

    // Detail panel close button
    var closeBtn = document.getElementById("dgDetailClose");
    if (closeBtn) {
        closeBtn.addEventListener("click", function (e) {
            e.stopPropagation();
            deselectAll();
            closeDetailPanel();
        });
    }

    // Handle window resize for vis.js
    window.addEventListener("resize", function () {
        if (network) {
            // Small delay to let the container resize
            setTimeout(function () { network.redraw(); }, 100);
        }
    });

})();