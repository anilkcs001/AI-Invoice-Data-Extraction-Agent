/**
 * @file app.js
 * @description Main application logic for the Extension Impact Analyzer.
 *
 * Exposes three window functions called by AL:
 *   - LoadExtensions(json)    — populates the picker dropdown
 *   - ShowImpactResult(json)  — renders impact analysis results
 *   - SetAnalyzing(bool)      — shows/hides loading state
 *
 * Fires three events to AL:
 *   - OnReady                 — (handled by startup.js)
 *   - OnExtensionSelected     — when user picks from dropdown
 *   - OnAnalyzeRequested      — when user clicks Analyze button
 */
(function () {
    "use strict";

    // ═══════════════════════════════════════════════════════════════
    // State
    // ═══════════════════════════════════════════════════════════════
    var allExtensions = [];
    var selectedExt = null;
    var lastResult = null;
    var activeFilter = "all";
    var eventsWired = false;
    var isDark = true;
    var pickerOpen = false;

    var TYPE_COLORS = {
        ms: "#3b82f6",
        isv: "#10b981",
        custom: "#f43f5e",
        ext: "#8b5cf6"
    };

    var STATUS_COLORS = {
        red: "#ef4444",
        amber: "#f59e0b",
        green: "#22c55e",
        grey: "#6b7280"
    };

    var STATUS_LABELS = {
        red: "BREAKING",
        amber: "WARNING",
        green: "SAFE",
        grey: "UNKNOWN"
    };

    var STATUS_ICONS = {
        red: "&#x1F534;",
        amber: "&#x1F7E1;",
        green: "&#x1F7E2;",
        grey: "&#x26AB;"
    };

    // ═══════════════════════════════════════════════════════════════
    // window.LoadExtensions — called by AL after OnReady
    // ═══════════════════════════════════════════════════════════════

    /**
     * Parses the extensions JSON and populates the picker dropdown.
     * @param {string} jsonPayload - JSON: { extensions: [{id,name,publisher,version,type},...] }
     */
    window.LoadExtensions = function (jsonPayload) {
        var data;
        try { data = JSON.parse(jsonPayload); } catch (e) { return; }
        if (!data || !data.extensions) return;

        allExtensions = data.extensions;
        allExtensions.sort(function (a, b) {
            return (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase());
        });

        var statEl = document.getElementById("iaStatNum");
        if (statEl) statEl.textContent = String(allExtensions.length);

        renderPickerList("");
        selectedExt = null;
        resetInputPanel();
        hideResults();

        if (!eventsWired) {
            wireEvents();
            eventsWired = true;
        }
    };

    // ═══════════════════════════════════════════════════════════════
    // window.ShowImpactResult — called by AL after analysis completes
    // ═══════════════════════════════════════════════════════════════

    /**
     * Renders the full impact analysis result.
     * @param {string} jsonPayload - The impact result JSON from AL
     */
    window.ShowImpactResult = function (jsonPayload) {
        var data;
        try { data = JSON.parse(jsonPayload); } catch (e) { return; }
        if (!data) return;

        lastResult = data;
        activeFilter = "all";

        renderRiskBanner(data);
        renderSummary(data.summary);
        renderFilterPills(data.summary);
        renderDependentCards(data.dependents, "all");

        var resultsEl = document.getElementById("iaResults");
        if (resultsEl) {
            resultsEl.classList.remove("ia-hidden");
            resultsEl.classList.add("ia-fade-in");
            setTimeout(function () {
                resultsEl.scrollIntoView({ behavior: "smooth", block: "start" });
            }, 100);
        }
    };

    // ═══════════════════════════════════════════════════════════════
    // window.SetAnalyzing — called by AL to show/hide loading state
    // ═══════════════════════════════════════════════════════════════

    /**
     * Shows or hides the loading spinner on the Analyze button.
     * @param {boolean} isAnalyzing - true to show spinner, false to hide
     */
    window.SetAnalyzing = function (isAnalyzing) {
        var btn = document.getElementById("iaAnalyzeBtn");
        var spinner = document.getElementById("iaBtnSpinner");
        var btnText = btn ? btn.querySelector(".ia-btn-text") : null;

        if (isAnalyzing) {
            if (btn) btn.disabled = true;
            if (btnText) btnText.textContent = "Analyzing...";
            if (spinner) spinner.classList.remove("ia-hidden");
        } else {
            if (btn) btn.disabled = !isFormValid();
            if (btnText) btnText.textContent = "Analyze Impact";
            if (spinner) spinner.classList.add("ia-hidden");
        }
    };

    // ═══════════════════════════════════════════════════════════════
    // Picker
    // ═══════════════════════════════════════════════════════════════

    function renderPickerList(searchText) {
        var listEl = document.getElementById("iaPickerList");
        if (!listEl) return;

        var q = (searchText || "").toLowerCase();
        var filtered = allExtensions.filter(function (ext) {
            if (!q) return true;
            return (ext.name || "").toLowerCase().indexOf(q) !== -1 ||
                   (ext.publisher || "").toLowerCase().indexOf(q) !== -1;
        });

        if (filtered.length === 0) {
            listEl.innerHTML = '<div class="ia-picker-empty">No extensions match</div>';
            return;
        }

        var html = "";
        for (var i = 0; i < filtered.length; i++) {
            var ext = filtered[i];
            var col = TYPE_COLORS[ext.type] || TYPE_COLORS.ext;
            var isActive = selectedExt && selectedExt.id === ext.id;

            html += '<div class="ia-picker-option' + (isActive ? ' ia-picker-option-on' : '') + '" data-id="' + esc(ext.id) + '">';
            html += '<span class="ia-picker-dot" style="background:' + col + '"></span>';
            html += '<div class="ia-picker-opt-info">';
            html += '<span class="ia-picker-opt-name">' + esc(ext.name) + '</span>';
            html += '<span class="ia-picker-opt-meta">' + esc(ext.publisher) + ' — v' + esc(ext.version) + '</span>';
            html += '</div>';
            html += '</div>';
        }

        listEl.innerHTML = html;
    }

    function openPicker() {
        var dd = document.getElementById("iaPickerDropdown");
        var search = document.getElementById("iaPickerSearch");
        if (dd) dd.classList.remove("ia-hidden");
        if (search) { search.value = ""; search.focus(); }
        renderPickerList("");
        pickerOpen = true;
    }

    function closePicker() {
        var dd = document.getElementById("iaPickerDropdown");
        if (dd) dd.classList.add("ia-hidden");
        pickerOpen = false;
    }

    function selectExtension(id) {
        var ext = null;
        for (var i = 0; i < allExtensions.length; i++) {
            if (allExtensions[i].id === id) { ext = allExtensions[i]; break; }
        }
        if (!ext) return;

        selectedExt = ext;
        closePicker();

        // Update trigger text
        var trigger = document.getElementById("iaPickerTrigger");
        if (trigger) {
            var col = TYPE_COLORS[ext.type] || TYPE_COLORS.ext;
            trigger.innerHTML =
                '<span class="ia-picker-dot" style="background:' + col + '"></span>' +
                '<span class="ia-picker-text">' + esc(ext.name) + '</span>' +
                '<svg class="ia-picker-arrow" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>';
        }

        // Show current version
        var curVerEl = document.getElementById("iaCurrentVer");
        if (curVerEl) {
            curVerEl.textContent = "Currently installed: v" + ext.version;
            curVerEl.classList.remove("ia-hidden");
        }

        // Pre-fill version: auto-increment Major by 1
        var parts = (ext.version || "0.0.0.0").split(".");
        var curMajor = parseInt(parts[0]) || 0;
        setVerInput("iaMajor", curMajor + 1);
        setVerInput("iaMinor", 0);
        setVerInput("iaBuild", 0);
        setVerInput("iaRevision", 0);
        updateVersionPreview();
        validateForm();

        // Fire callback to AL
        try {
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnExtensionSelected", [
                ext.id, ext.name, ext.version
            ]);
        } catch (ex) { /* ok */ }
    }

    // ═══════════════════════════════════════════════════════════════
    // Version Input
    // ═══════════════════════════════════════════════════════════════

    function getVerInput(id) {
        var el = document.getElementById(id);
        if (!el) return 0;
        var val = parseInt(el.value);
        return isNaN(val) || val < 0 ? 0 : val;
    }

    function setVerInput(id, val) {
        var el = document.getElementById(id);
        if (el) el.value = String(val);
    }

    function getNewVersion() {
        return {
            major: getVerInput("iaMajor"),
            minor: getVerInput("iaMinor"),
            build: getVerInput("iaBuild"),
            revision: getVerInput("iaRevision")
        };
    }

    function formatVer(v) {
        return v.major + "." + v.minor + "." + v.build + "." + v.revision;
    }

    function updateVersionPreview() {
        var v = getNewVersion();
        var previewEl = document.getElementById("iaVerPreview");
        if (previewEl) previewEl.textContent = "New version: " + formatVer(v);
    }

    function validateForm() {
        var errorEl = document.getElementById("iaVerError");
        var btn = document.getElementById("iaAnalyzeBtn");
        var v = getNewVersion();
        var error = "";

        if (!selectedExt) {
            if (btn) btn.disabled = true;
            return false;
        }

        if (v.major === 0 && v.minor === 0 && v.build === 0 && v.revision === 0) {
            error = "Version cannot be 0.0.0.0";
        }

        if (!error && selectedExt) {
            var curVer = selectedExt.version || "0.0.0.0";
            if (formatVer(v) === curVer) {
                error = "New version must differ from current version (" + curVer + ")";
            }
        }

        if (errorEl) {
            if (error) {
                errorEl.textContent = error;
                errorEl.classList.remove("ia-hidden");
            } else {
                errorEl.classList.add("ia-hidden");
            }
        }

        var valid = !error && selectedExt;
        if (btn) btn.disabled = !valid;
        return valid;
    }

    function isFormValid() {
        var v = getNewVersion();
        if (!selectedExt) return false;
        if (v.major === 0 && v.minor === 0 && v.build === 0 && v.revision === 0) return false;
        if (formatVer(v) === (selectedExt.version || "0.0.0.0")) return false;
        return true;
    }

    function resetInputPanel() {
        var trigger = document.getElementById("iaPickerTrigger");
        if (trigger) {
            trigger.innerHTML =
                '<span class="ia-picker-text">Choose an extension...</span>' +
                '<svg class="ia-picker-arrow" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>';
        }
        var curVerEl = document.getElementById("iaCurrentVer");
        if (curVerEl) curVerEl.classList.add("ia-hidden");
        setVerInput("iaMajor", 0);
        setVerInput("iaMinor", 0);
        setVerInput("iaBuild", 0);
        setVerInput("iaRevision", 0);
        updateVersionPreview();
        var btn = document.getElementById("iaAnalyzeBtn");
        if (btn) btn.disabled = true;
        var errorEl = document.getElementById("iaVerError");
        if (errorEl) errorEl.classList.add("ia-hidden");
    }

    // ═══════════════════════════════════════════════════════════════
    // Results Rendering
    // ═══════════════════════════════════════════════════════════════

    function renderRiskBanner(data) {
        var bannerEl = document.getElementById("iaRiskBanner");
        if (!bannerEl) return;

        var risk = data.overallRisk || "none";
        var msg = data.overallMessage || "";
        var target = data.targetApp || {};

        var riskClass = "ia-risk-" + risk;
        var icon = "";
        if (risk === "high") icon = "&#x1F534;";
        else if (risk === "medium") icon = "&#x1F7E1;";
        else if (risk === "low") icon = "&#x1F7E2;";
        else icon = "&#x2139;&#xFE0F;";

        var pulse = (risk === "high" || risk === "medium") ? " ia-pulse" : "";

        bannerEl.className = "ia-risk-banner " + riskClass + pulse;
        bannerEl.innerHTML =
            '<div class="ia-risk-left">' +
            '  <span class="ia-risk-icon">' + icon + '</span>' +
            '  <div class="ia-risk-info">' +
            '    <div class="ia-risk-title">' + getRiskTitle(risk) + '</div>' +
            '    <div class="ia-risk-msg">' + esc(msg) + '</div>' +
            '  </div>' +
            '</div>' +
            '<div class="ia-risk-right">' +
            '  <div class="ia-risk-ver">' + esc(target.name || "") + '</div>' +
            '  <div class="ia-risk-ver-change">v' + esc(target.oldVersion || "") + ' → v' + esc(target.newVersion || "") + '</div>' +
            '</div>';
    }

    function getRiskTitle(risk) {
        if (risk === "high") return "HIGH RISK — Do not publish without fixing";
        if (risk === "medium") return "MEDIUM RISK — Recompile and retest dependents";
        if (risk === "low") return "LOW RISK — Safe to publish";
        return "NO IMPACT — Nothing depends on this extension";
    }

    function renderSummary(summary) {
        var el = document.getElementById("iaSummary");
        if (!el || !summary) return;

        el.innerHTML =
            buildSumCard("green", "Safe", summary.green || 0) +
            buildSumCard("amber", "Warning", summary.amber || 0) +
            buildSumCard("red", "Breaking", summary.red || 0) +
            buildSumCard("grey", "Unknown", summary.grey || 0);
    }

    function buildSumCard(status, label, count) {
        var col = STATUS_COLORS[status] || "#6b7280";
        return '<div class="ia-sum-card">' +
            '<div class="ia-sum-num" style="color:' + col + '">' + count + '</div>' +
            '<div class="ia-sum-label">' + label + '</div>' +
            '</div>';
    }

    function renderFilterPills(summary) {
        var el = document.getElementById("iaFilterRow");
        if (!el || !summary) return;

        var total = (summary.green || 0) + (summary.amber || 0) + (summary.red || 0) + (summary.grey || 0);

        var pills = [
            { key: "all", label: "All", count: total },
            { key: "red", label: "Breaking", count: summary.red || 0 },
            { key: "amber", label: "Warning", count: summary.amber || 0 },
            { key: "green", label: "Safe", count: summary.green || 0 },
            { key: "grey", label: "Unknown", count: summary.grey || 0 }
        ];

        var html = "";
        for (var i = 0; i < pills.length; i++) {
            var p = pills[i];
            if (p.key !== "all" && p.count === 0) continue;
            var isOn = (activeFilter === p.key);
            var style = "";
            if (isOn && p.key !== "all" && STATUS_COLORS[p.key]) {
                style = ' style="background:' + STATUS_COLORS[p.key] + ';color:#fff;border-color:' + STATUS_COLORS[p.key] + '"';
            }
            html += '<button class="ia-pill' + (isOn ? ' ia-pill-on' : '') + '" data-status="' + p.key + '"' + style + '>';
            html += STATUS_ICONS[p.key] ? STATUS_ICONS[p.key] + " " : "";
            html += p.label;
            html += '<span class="ia-pill-count">' + p.count + '</span>';
            html += '</button>';
        }

        el.innerHTML = html;
        wireFilterClicks();
    }

    function renderDependentCards(dependents, filter) {
        var el = document.getElementById("iaDepList");
        if (!el) return;

        if (!dependents || dependents.length === 0) {
            el.innerHTML = '<div class="ia-no-deps">No dependent extensions found. This extension can be safely updated.</div>';
            return;
        }

        var filtered = dependents;
        if (filter !== "all") {
            filtered = dependents.filter(function (d) { return d.status === filter; });
        }

        if (filtered.length === 0) {
            el.innerHTML = '<div class="ia-no-deps">No extensions match this filter.</div>';
            return;
        }

        var html = "";
        for (var i = 0; i < filtered.length; i++) {
            html += buildDepCard(filtered[i], i);
        }
        el.innerHTML = html;
    }

    function buildDepCard(dep, index) {
        var status = dep.status || "grey";
        var col = STATUS_COLORS[status] || STATUS_COLORS.grey;
        var typeCol = TYPE_COLORS[dep.type] || TYPE_COLORS.ext;
        var delay = (index * 0.06);

        var s = '';
        s += '<div class="ia-dep-card ia-dep-' + status + '" style="animation-delay:' + delay + 's">';

        // Header row
        s += '<div class="ia-dep-header">';
        s += '  <div class="ia-dep-header-left">';
        s += '    <span class="ia-dep-status-badge" style="background:' + col + '">' + (STATUS_LABELS[status] || "UNKNOWN") + '</span>';
        s += '    <div class="ia-dep-name-block">';
        s += '      <div class="ia-dep-name">' + esc(dep.name || "Unknown") + '</div>';
        s += '      <div class="ia-dep-meta">';
        s += '        <span class="ia-dep-type-dot" style="background:' + typeCol + '"></span>';
        s += '        ' + esc(dep.publisher || "") + ' · v' + esc(dep.version || "") + '';
        s += '      </div>';
        s += '    </div>';
        s += '  </div>';
        s += '</div>';

        // Version range
       var rangeText = "";
        if (dep.minVersion && dep.minVersion !== "0.0.0.0" && dep.minVersion !== "") {
            if (dep.maxVersion && dep.maxVersion !== "0.0.0.0" && dep.maxVersion !== "") {
                rangeText = "Compiled against: v" + dep.minVersion + " — v" + dep.maxVersion;
            } else {
                rangeText = "Compiled against: v" + dep.minVersion;
            }
        } else {
            rangeText = "Dependency version info not available";
        }

        s += '<div class="ia-dep-range">';
        s += '  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4h16v16H4z"/><path d="M9 9h6M9 13h4"/></svg>';
        s += '  <span>' + rangeText + '</span>';
        s += '</div>';

        // Reason
        if (dep.reason) {
            s += '<div class="ia-dep-reason">';
            s += '  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>';
            s += '  <span>' + esc(dep.reason) + '</span>';
            s += '</div>';
        }

        // Action
        if (dep.action) {
            s += '<div class="ia-dep-action">';
            s += '  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 18l6-6-6-6"/></svg>';
            s += '  <span>' + esc(dep.action) + '</span>';
            s += '</div>';
        }

        s += '</div>';
        return s;
    }

    function hideResults() {
        var el = document.getElementById("iaResults");
        if (el) {
            el.classList.add("ia-hidden");
            el.classList.remove("ia-fade-in");
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Event Wiring
    // ═══════════════════════════════════════════════════════════════

    function wireEvents() {

        // ── Picker trigger click ────────────────────────────────
        var trigger = document.getElementById("iaPickerTrigger");
        if (trigger) {
            trigger.addEventListener("click", function (evt) {
                evt.stopPropagation();
                if (pickerOpen) { closePicker(); } else { openPicker(); }
            });
        }

        // ── Picker search input ─────────────────────────────────
        var searchEl = document.getElementById("iaPickerSearch");
        if (searchEl) {
            searchEl.addEventListener("input", function () {
                renderPickerList(searchEl.value || "");
            });
            searchEl.addEventListener("click", function (evt) {
                evt.stopPropagation();
            });
        }

        // ── Picker list click (event delegation) ────────────────
        var listEl = document.getElementById("iaPickerList");
        if (listEl) {
            listEl.addEventListener("click", function (evt) {
                evt.stopPropagation();
                var target = evt.target;
                var maxUp = 10;
                while (target && maxUp > 0) {
                    if (target.classList && target.classList.contains("ia-picker-option")) {
                        var id = target.getAttribute("data-id");
                        if (id) selectExtension(id);
                        return;
                    }
                    if (target === listEl) return;
                    target = target.parentElement;
                    maxUp--;
                }
            });
        }

        // ── Click outside picker to close ───────────────────────
        document.addEventListener("click", function (evt) {
            if (pickerOpen) {
                var picker = document.getElementById("iaPicker");
                if (picker && !picker.contains(evt.target)) {
                    closePicker();
                }
            }
        });

        // ── Version input changes ───────────────────────────────
        var verIds = ["iaMajor", "iaMinor", "iaBuild", "iaRevision"];
        for (var v = 0; v < verIds.length; v++) {
            var verEl = document.getElementById(verIds[v]);
            if (verEl) {
                verEl.addEventListener("input", function () {
                    updateVersionPreview();
                    validateForm();
                });
                verEl.addEventListener("change", function () {
                    if (this.value === "" || parseInt(this.value) < 0) this.value = "0";
                    updateVersionPreview();
                    validateForm();
                });
            }
        }

        // ── Analyze button click ────────────────────────────────
        var btn = document.getElementById("iaAnalyzeBtn");
        if (btn) {
            btn.addEventListener("click", function () {
                if (!isFormValid() || !selectedExt) return;
                var ver = getNewVersion();

                try {
                    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OnAnalyzeRequested", [
                        selectedExt.id,
                        ver.major,
                        ver.minor,
                        ver.build,
                        ver.revision
                    ]);
                } catch (ex) {
                    console.error("OnAnalyzeRequested failed:", ex);
                }
            });
        }

        // ── Theme toggle ────────────────────────────────────────
        var themeBtn = document.getElementById("iaThemeToggle");
        if (themeBtn) {
            themeBtn.addEventListener("click", function () {
                isDark = !isDark;
                var root = document.querySelector(".ia-root");
                if (root) {
                    root.classList.toggle("ia-dark", isDark);
                    root.classList.toggle("ia-light", !isDark);
                }
                var icon = document.getElementById("iaThemeIcon");
                if (icon) icon.innerHTML = isDark ? "&#9788;" : "&#9790;";
            });
        }
    }

    function wireFilterClicks() {
        var el = document.getElementById("iaFilterRow");
        if (!el) return;

        var pills = el.querySelectorAll(".ia-pill");
        for (var i = 0; i < pills.length; i++) {
            pills[i].addEventListener("click", (function (pill) {
                return function (evt) {
                    evt.stopPropagation();
                    var status = pill.getAttribute("data-status");
                    if (status && status !== activeFilter && lastResult) {
                        activeFilter = status;
                        renderFilterPills(lastResult.summary);
                        renderDependentCards(lastResult.dependents, activeFilter);
                    }
                };
            })(pills[i]));
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Utilities
    // ═══════════════════════════════════════════════════════════════

    function esc(str) {
        if (!str) return "";
        var d = document.createElement("div");
        d.appendChild(document.createTextNode(str));
        return d.innerHTML;
    }

})();
