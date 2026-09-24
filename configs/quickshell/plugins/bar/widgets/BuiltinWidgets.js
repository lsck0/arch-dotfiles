.pragma library

/*
 * ─────────────────────────────────────────────────────────────────────────────
 * BuiltinWidgets — cold-start id → file map for the widgets in this directory
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * WHY IT EXISTS. PluginRegistry's manifest scan is a subprocess, so on a cold
 * boot there is a window where no widget id resolves to anything. The bar must
 * not depend on that scan for its OWN widgets: without this map the first frame
 * creates empty Loaders and never paints a bar at all.
 *
 * So this is a mirror of the `*.manifest.json` files next to it, and the
 * manifest stays the authority — `BarSection` asks the registry first and only
 * falls back here. A mirror can drift, and a drifted entry fails as a widget
 * that silently never appears, which is the worst way for it to fail.
 * `checkDrift` is the guard: it runs once per session after the first scan
 * completes and names any manifest with no entry here, or any entry here with
 * no manifest.
 *
 * The map cannot be computed from the id. `bar.audio-io` is `AudioIO.qml`, not
 * the `AudioIo.qml` a kebab-to-pascal rule produces, and one special case in a
 * derivation rule is worse than a table you can read.
 */

const files = {
    "bar.active-window":   "ActiveWindow.qml",
    "bar.agents":          "Agents.qml",
    "bar.app-menu":        "AppMenu.qml",
    "bar.audio-io":        "AudioIO.qml",
    "bar.battery":         "Battery.qml",
    "bar.clock":           "Clock.qml",
    "bar.costs":           "Costs.qml",
    "bar.discord":         "Discord.qml",
    "bar.display":         "Display.qml",
    "bar.homelab":         "Homelab.qml",
    "bar.exit":            "Exit.qml",
    "bar.indicators":      "Indicators.qml",
    "bar.keyboard-layout": "KeyboardLayout.qml",
    "bar.media":           "Media.qml",
    "bar.microphone":      "Microphone.qml",
    "bar.network":         "Network.qml",
    "bar.news":            "News.qml",
    "bar.notifications":   "Notifications.qml",
    "bar.obs":             "Obs.qml",
    "bar.separator":       "Separator.qml",
    "bar.spacer":          "Spacer.qml",
    "bar.system":          "System.qml",
    "bar.system-update":   "SystemUpdate.qml",
    "bar.toggles":         "Toggles.qml",
    "bar.tray":            "Tray.qml",
    "bar.weather":         "Weather.qml",
    "bar.workspaces":      "Workspaces.qml"
};

// "" for an id this directory does not ship, which is the normal answer for a third-party widget and means "let the registry handle it".
function fileFor(id) {
    return files[String(id || "")] || "";
}

// One report per session, not one per bar per section — six identical warnings teach nothing the first did not.
let checked = false;

/*
 * Cross-check the map against what the scan actually found. `installedPlugins`
 * is PluginRegistry's id → manifest object; only first-party bar-widget
 * manifests are compared, since everything else legitimately has no entry here.
 *
 * Call after the first successful scan. A drift here is a programmer error —
 * someone added a widget and updated one of the two places — so it is reported
 * loudly rather than worked around.
 */
function checkDrift(installedPlugins, warn) {
    if (checked) return;
    if (!installedPlugins) return;
    checked = true;

    const seen = {};
    for (const id in installedPlugins) {
        const manifest = installedPlugins[id];
        if (!manifest || !manifest.__isFirstParty) continue;
        if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("bar-widget") === -1) continue;
        seen[id] = true;
        if (!files[id])
            warn("BuiltinWidgets: manifest '" + id + "' has no cold-start entry — "
                + "the widget will not render until the plugin scan finishes");
    }

    for (const id in files) {
        if (!seen[id])
            warn("BuiltinWidgets: '" + id + "' -> " + files[id]
                + " has no first-party manifest — the entry is dead or the manifest was lost");
    }
}
