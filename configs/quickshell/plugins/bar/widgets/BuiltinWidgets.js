.pragma library

// cold-start mirror of the manifests, id -> file
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
    "bar.ossec":           "Ossec.qml",
    "bar.separator":       "Separator.qml",
    "bar.spacer":          "Spacer.qml",
    "bar.system":          "System.qml",
    "bar.system-update":   "SystemUpdate.qml",
    "bar.toggles":         "Toggles.qml",
    "bar.tray":            "Tray.qml",
    "bar.weather":         "Weather.qml",
    "bar.workspaces":      "Workspaces.qml"
};

// "" means let the registry handle it
function fileFor(id) {
    return files[String(id || "")] || "";
}

// report once per session
let checked = false;

// call after the first successful scan
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
            warn("BuiltinWidgets: manifest '" + id + "' has no cold-start entry, "
                + "the widget will not render until the plugin scan finishes");
    }

    for (const id in files) {
        if (!seen[id])
            warn("BuiltinWidgets: '" + id + "' -> " + files[id]
                + " has no first-party manifest: the entry is dead or the manifest was lost");
    }
}
