import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "plugins/bar"
import "plugins/background"
import "plugins/osd"
import "plugins/clipboard"
import "plugins/appsearch"
import "plugins/power"
import "plugins/overview"
import "plugins/startup"
import "services"

// Entry point. quickshell Phase 2: dynamic plugin registry — see
// services/PluginRegistry.qml's own header for what's a faithful 1:1 port
// vs. what's adapted for this repo (no OMARCHY_PATH/distro checkout, no
// bundled second config layer, no swappable alternative-bar plugins since
// none exist or are planned here).
//
// One Bar per connected screen, matching Quickshell's standard per-monitor
// panel pattern (Variants over Quickshell.screens) — kept as a direct
// instantiation rather than porting upstream's swappable-bar-option Loader
// machinery (defaultBarLoader/pluginBarLoader/activeBarId), since this repo
// has exactly one bar implementation and no "bar" kind plugin is planned to
// ever compete with it.
//
// Background and Osd instantiate their own per-screen Variants internally.
// Locking is owned entirely by hyprlock/hypridle (configs/hyprland/) —
// quickshell's own lock plugin was removed 2026-09-08 in favor of that.
//
// ---------------------------------------------------------------------------
// TWO WAYS A PIECE OF UI GETS INTO THIS SHELL, and which to use
// ---------------------------------------------------------------------------
//
// 1. Declared here, at the bottom of this file (Background, Osd, Clipboard,
//    AppSearch, PowerMenu, Overview, Startup). Always loaded, always alive,
//    no manifest. Correct for the fixtures of the desktop itself: things with
//    no meaningful "disabled" state, that own an IpcHandler other components
//    call into, and that nothing should be able to unregister at runtime.
//
// 2. A plugin directory with a `manifest.json`, discovered by PluginRegistry
//    and loaded on demand by kind — `bar-widget` into the bar's layout,
//    `panel`/`overlay`/`menu` through summon()/hide()/toggle(), `service` into
//    serviceHost. Correct for anything optional, placeable, user-enableable,
//    or shipped by someone other than this repo. A plugin owning a
//    long-running subprocess must additionally set `"keepLoaded": true`, or
//    its Loader tears the Process down before it can exit and orphans the
//    children.
//
// The split is deliberate, not historical drift: mechanism 2 costs a manifest,
// an async scan and a Loader per entry, which buys nothing for a component
// that is unconditionally present. If a new component could reasonably be
// turned off, moved, or replaced, it wants a manifest; otherwise it belongs in
// the list at the bottom of this file.
ShellRoot {
  id: shell

  // Shared service instances, injected into Bar via property (relative-path
  // imports don't share singleton state across importers, so these are
  // regular instances built once here and handed down).
  property PluginRegistry pluginRegistry: PluginRegistry { }
  property AppLibrary appLibrary: AppLibrary { }

  readonly property string home: Quickshell.env("HOME")
  // Quickshell.shellDir is this checkout's own shell.qml directory
  // (~/.config/quickshell, symlinked to configs/quickshell/ in the repo) —
  // the direct substitute for upstream's OMARCHY_PATH-derived shellPath,
  // no env var needed.
  readonly property string shellDir: Quickshell.shellDir
  readonly property string firstPartyPluginsDir: shellDir + "/plugins"
  // Deliberately under XDG_STATE_HOME, not inside the ~/.config/quickshell
  // symlink: that path resolves into this git-tracked repo, and shell.json
  // is runtime state (bar layout, enabled plugins), not tracked config —
  // same reasoning as toggles/lib.sh's TOGGLES_STATE_DIR.
  readonly property string userConfigPath:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/quickshell/shell.json"

  // This repo's actual current bar layout, as the sole "defaults" — no
  // separate bundled/distro-defaults file exists to layer on top of this
  // (upstream has defaultsPath + userConfigPath as two layers; this repo
  // only ever had the one).
  readonly property var builtinShellConfig: ({
    version: 1,
    bar: {
      layout: {
        // The launcher and the workspaces: where you are, and how to get
        // somewhere else. Both are navigation rather than information, which
        // is why they sit at the edge you throw the pointer at.
        left: [
          { id: "bar.app-menu" },
          { id: "bar.workspaces" }
        ],
        // The centre is for what is happening RIGHT NOW: what is playing, and
        // who is in the call. Both are transient and both are things you look
        // at deliberately rather than scan, which is what the middle of a bar
        // is good for.
        // Clock and weather lead the centre as a pair — they are the two
        // always-present readouts, so they are what the centre is anchored on.
        // Media and the Discord call trail them and come and go.
        center: [
          { id: "bar.clock" }, { id: "bar.weather" },
          { id: "bar.media" }, { id: "bar.discord" }
        ],
        // active-window/agents/microphone/news/costs dropped 2026-09-01 per
        // an explicit per-widget review against the SPEC: costs was
        // non-functional (needs credentials that don't exist), microphone
        // only shortcut into AudioIO's own panel, and active-window was the
        // one variable-width widget competing for space the SPEC's middle
        // section needs. Their .qml/.manifest.json stay on disk, so
        // re-adding any of them is one array entry.
        // Keep this in sync with ~/.local/state/quickshell/shell.json, which
        // overrides it whenever it exists. A fresh machine (or a deleted state
        // file) reproduces *this* list, so drift here ships the wrong bar.
        right: [
          // ONE separator, and only where it earns its place: between the
          // widgets that come and go and the ones that are always there.
          //
          // Rules between permanent widgets were noise — they never divide
          // anything that changes, so they add a line to look at for no
          // information. The transient boundary is different: OBS and the tray
          // appear and vanish, and without a rule the permanent cluster looks
          // like it simply grew a new icon.
          //
          // Transient first on purpose: the section is right-aligned, so things
          // appearing here grow the cluster leftward into empty space and every
          // permanent icon keeps its position. The separator hides itself when
          // the whole transient group is empty.
          // Self-hiding, like OBS and the tray: it is only on the bar when
          // `checkupdates` actually reports something, so it costs nothing on
          // an up-to-date system. It was left out of this list while its click
          // action pointed at a script that did not exist; that is fixed (see
          // SystemUpdate.qml / scripts/system-update.sh), so it earns its slot.
          { id: "bar.system-update" },
          { id: "bar.obs" },
          { id: "bar.tray" },
          { id: "bar.separator" },
          { id: "bar.system" },
          { id: "bar.network" }, { id: "bar.display" }, { id: "bar.audio-io" },
          { id: "bar.notifications" },
          { id: "bar.keyboard-layout" },
          { id: "bar.indicators" },
          { id: "bar.exit" }
        ]
      },
      // What the bar shows on every screen that is NOT the main one. The
      // status widgets are all global state — clock, battery, network, tray —
      // so repeating them per monitor says the same thing several times while
      // costing a full set of poll timers and MPRIS/tray subscriptions each.
      // What is actually per-screen is which workspace you are on, plus a way
      // into the launcher.
      //
      // Set `bar.mainScreen` in shell.json to name the main output
      // explicitly; otherwise the output at 0,0 wins (which is DP-1 on the
      // desktop, per configs/hyprland/hyprland_monitors.lua) and a
      // single-monitor machine is unaffected either way.
      secondaryLayout: {
        left: [{ id: "bar.app-menu" }, { id: "bar.workspaces" }],
        center: [],
        right: []
      }
    },
    plugins: []
  })

  property var shellConfig: builtinShellConfig

  onShellConfigChanged: {
    pluginRegistry.registryRevision++
    pluginRegistry.pluginsChanged()
  }

  function applyShellConfig() {
    var userText = userConfigFile.text() || ""
    if (userText.trim()) {
      try {
        var parsed = JSON.parse(userText)
        if (Util.isPlainObject(parsed) && parsed.version === 1) {
          shellConfig = parsed
          return
        }
        console.warn("shell.json missing version: 1, using builtin defaults")
      } catch (e) {
        console.warn("shell.json parse failed, using builtin defaults:", e)
      }
    }
    shellConfig = builtinShellConfig
  }

  function persistShellConfig(nextConfig) {
    var payload = Util.cloneJson(nextConfig)
    payload.version = 1
    shellConfig = payload
    userConfigFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function mutateShellConfig(mutator) {
    var copy = Util.cloneJson(shellConfig || builtinShellConfig)
    mutator(copy)
    persistShellConfig(copy)
  }

  // ------------------------------------------------------- widget settings
  //
  // Per-widget state a widget saves for itself: the tray's pinned/hidden item
  // ids today, anything comparable later. Its own file, deliberately NOT
  // shell.json.
  //
  // THIS USED TO WRITE INTO shell.json's LAYOUT, and that is a trap rather
  // than a style question. shell.json does not exist on a fresh install, so
  // the bar comes from `builtinShellConfig` above — which means shell.qml is
  // the source of truth for the layout and editing this file changes the bar.
  // But any write to shell.json snapshots the WHOLE config, layout included.
  // So the first time anyone pinned a tray icon, the then-current layout was
  // frozen to disk and every later edit to builtinShellConfig was silently
  // ignored from that moment on: the bar would simply stop tracking the file
  // that appears to define it, with no error and no obvious cause.
  //
  // Pinning an icon is not a statement about bar layout, so it no longer
  // writes one. shell.json is now only ever written by a deliberate layout
  // change (moveBarWidget / setBarWidget / setEnabled through IPC), which is
  // exactly when snapshotting it is the correct behaviour.
  readonly property string widgetSettingsPath:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/quickshell/widget-settings.json"

  // { widgetId: { ...settings } }
  property var widgetSettings: ({})

  function settingsForWidget(widgetId) {
    var entry = widgetSettings[String(widgetId)]
    return Util.isPlainObject(entry) ? entry : ({})
  }

  // Returns true if anything actually changed, so a caller that saves on every
  // state change does not rewrite an identical file.
  function setWidgetSettings(widgetId, settings) {
    var key = String(widgetId)
    var next = {}
    for (var k in settings) if (k !== "id") next[k] = settings[k]
    var current = widgetSettings[key]
    if (current && JSON.stringify(current) === JSON.stringify(next)) return false
    widgetSettings = Util.mapSet(widgetSettings, key, next)
    widgetSettingsFile.setText(JSON.stringify(widgetSettings, null, 2) + "\n")
    return true
  }

  function applyWidgetSettings() {
    var text = widgetSettingsFile.text() || ""
    if (!text.trim()) {
      widgetSettings = ({})
      return
    }
    try {
      var parsed = JSON.parse(text)
      widgetSettings = Util.isPlainObject(parsed) ? parsed : ({})
    } catch (e) {
      console.warn("widget-settings.json parse failed, ignoring it:", e)
      widgetSettings = ({})
    }
  }

  FileView {
    id: widgetSettingsFile
    path: shell.widgetSettingsPath
    watchChanges: true
    atomicWrites: true
    // A missing file is the normal state on a fresh install, not an error.
    printErrors: false
    onLoaded: {
      shell.applyWidgetSettings()
      // atomicWrites replaces the inode this watch is attached to, so without
      // re-arming only the first external edit would ever be noticed.
      Util.rearmWatch(this)
    }
    onLoadFailed: shell.widgetSettings = ({})
    onFileChanged: reload()
  }

  // The user's shell.json REPLACES the builtin config rather than layering on
  // it, so a file written before `secondaryLayout` existed would leave it
  // undefined and every secondary bar would silently keep rendering the full
  // layout. Fill it (and only it) back in from the builtin when absent, so
  // the feature works on an existing install without anyone hand-editing
  // state. An explicit secondaryLayout in shell.json still wins.
  readonly property var barConfig: {
    var base = shellConfig && Util.isPlainObject(shellConfig.bar)
      ? shellConfig.bar : builtinShellConfig.bar
    if (base && base.secondaryLayout) return base
    var merged = Util.cloneJson(base)
    merged.secondaryLayout = builtinShellConfig.bar.secondaryLayout
    return merged
  }

  // Which output counts as "main". An explicit `bar.mainScreen` in shell.json
  // wins. Otherwise: whichever monitor Hyprland has assigned workspace 1 to
  // (configs/hyprland/hyprland_layout.lua's workspace_monitor table is the
  // single source of truth for that — on the desktop profile it pins
  // workspaces 1-4 to DP-2 and 5-9 to DP-1). That used to be "the output
  // positioned at 0,0" instead, which happened to be DP-1 on this desktop —
  // the SECONDARY monitor by workspace layout, not the one workspace 1 (and
  // therefore every fresh app) actually opens on. The main bar ended up on
  // the wrong screen as a result. Falls back to the old 0,0 heuristic, then
  // the first screen, if Hyprland hasn't reported workspace 1 yet (e.g. the
  // very first frame before any workspace has been created).
  readonly property string mainScreenName: {
    var configured = barConfig && barConfig.mainScreen ? String(barConfig.mainScreen) : ""
    if (configured) return configured
    var workspaces = Hyprland.workspaces.values
    for (var w = 0; w < workspaces.length; w++)
      if (workspaces[w].id === 1 && workspaces[w].monitor) return String(workspaces[w].monitor.name)
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].x === 0 && screens[i].y === 0) return String(screens[i].name)
    return screens.length > 0 ? String(screens[0].name) : ""
  }

  FileView {
    id: userConfigFile
    path: shell.userConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: shell.applyShellConfig()
    onLoadFailed: function(error) { shell.applyShellConfig() }
    onFileChanged: reload()
  }

  Component.onCompleted: {
    console.log("quickshell plugin registry",
      "shellDir=" + shell.shellDir,
      "firstPartyPluginsDir=" + shell.firstPartyPluginsDir,
      "userConfigPath=" + shell.userConfigPath)
    pluginRegistry.firstPartyDir = shell.firstPartyPluginsDir
    pluginRegistry.shellConfigProvider = function() { return shell.shellConfig }
    pluginRegistry.shellConfigMutator = function(mutate) { shell.mutateShellConfig(mutate) }
    // PluginRegistry.ensureUserDir() runs in its own Component.onCompleted and
    // chains rescan() once the directory exists. Kick a scan here too in case
    // the user dir already existed at startup.
    pluginRegistry.rescan()
    shell._syncServices()
  }

  // --------------------------------------------------------------- bar

  Variants {
    model: Quickshell.screens

    Bar {
      pluginRegistry: shell.pluginRegistry
      barConfig: shell.barConfig
      shellHost: shell
      // Bar derives isMainScreen from this and its own `modelData` — the
      // comparison cannot live here, because redeclaring Variants' required
      // `modelData` in this block shadows the one Variants injects and the
      // delegate then fails to construct at all.
      mainScreenName: shell.mainScreenName
    }
  }

  // ------------------------------------------------------------- services
  //
  // Generic loader for any enabled plugin that declares kind "service".
  // First-party infrastructure services are implicitly enabled by the registry;
  // third-party services are enabled by adding the plugin id to shell.json.
  Item {
    id: serviceHost
    visible: false
  }

  property var _services: ({})

  function serviceFor(pluginId) {
    return _services[String(pluginId)] || null
  }

  function ensureService(pluginId) {
    var key = String(pluginId)
    if (_services[key]) return _services[key]
    var manifest = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[key] : null
    if (!manifest) return null
    if (!Array.isArray(manifest.kinds) || manifest.kinds.indexOf("service") === -1) return null
    if (!manifest.entryPoints || !manifest.entryPoints.service) return null
    var url = pluginRegistry.entryPointUrl(manifest, "service")
    if (!url) return null

    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status !== Component.Ready) {
        console.warn("service plugin load failed for " + key + ": " + comp.errorString())
        return
      }
      var inst = comp.createObject(serviceHost)
      if (!inst) {
        console.warn("service plugin createObject returned null for", key)
        return
      }
      if ("shell" in inst) inst.shell = shell
      if ("manifest" in inst) inst.manifest = manifest
      if ("pluginRegistry" in inst) inst.pluginRegistry = shell.pluginRegistry
      _services = Util.mapSet(_services, key, inst)
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return _services[key] || null
  }

  function _syncServices() {
    if (!pluginRegistry || !pluginRegistry.installedPlugins) return
    var plugins = pluginRegistry.installedPlugins
    for (var id in plugins) {
      var m = plugins[id]
      if (!m) continue
      if (!Array.isArray(m.kinds) || m.kinds.indexOf("service") === -1) continue
      if (!m.entryPoints || !m.entryPoints.service) continue
      if (!pluginRegistry.isEnabled(id)) continue
      if (_services[id]) continue
      ensureService(id)
    }
    for (var existingId in _services) {
      var stillThere = plugins[existingId]
      var stillEnabled = stillThere && pluginRegistry.isEnabled(existingId)
      if (stillThere && stillEnabled) continue
      var inst = _services[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      _services = Util.mapRemove(_services, existingId)
    }
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { shell._syncServices() }
  }

  // ---------------------------------------------------------- on-demand panels
  //
  // For kinds "panel"/"overlay"/"menu" — none currently exist as first-party
  // manifests in this repo (AppMenu is a bar-widget, not a separate popup
  // plugin), but this stays wired so a later phase's panel/overlay/menu
  // plugin needs no further shell.qml changes to be summonable.

  property var openPanelIds: ({})
  property var pendingPayloads: ({})

  function summon(pluginId, payloadJson) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    if (!id) return false
    var plugins = shell.pluginRegistry.installedPlugins
    if (!plugins[id]) {
      console.warn("summon: unknown plugin", id)
      return false
    }
    if (!shell.pluginRegistry.isEnabled(id)) {
      console.warn("summon: plugin not enabled, not summoning:", id)
      return false
    }
    openPanelIds = Util.mapSet(openPanelIds, id, true)

    var queue = (pendingPayloads[id] || []).slice()
    queue.push(payloadJson || "")
    pendingPayloads = Util.mapSet(pendingPayloads, id, queue)

    deliverIfLoaded(id)
    return true
  }

  function hide(pluginId) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    if (!id) return false
    invokeIfLoaded(id, "close", null)
    if (!openPanelIds[id]) return true
    openPanelIds = Util.mapRemove(openPanelIds, id)
    return true
  }

  function isPluginOpen(pluginId) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    var loader = panelLoaders[id]
    if (loader && loader.item && loader.item.opened !== undefined)
      return loader.item.opened === true
    return openPanelIds[id] === true
  }

  function toggle(pluginId, payloadJson) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    return isPluginOpen(id) ? hide(id) : summon(id, payloadJson)
  }

  property var panelLoaders: ({})

  function registerPanelLoader(pluginId, loader) {
    panelLoaders = Util.mapSet(panelLoaders, pluginId, loader)
    deliverIfLoaded(pluginId)
  }

  function unregisterPanelLoader(pluginId) {
    if (!panelLoaders[pluginId]) return
    panelLoaders = Util.mapRemove(panelLoaders, pluginId)
  }

  function deliverIfLoaded(pluginId) {
    var loader = panelLoaders[pluginId]
    if (!loader || !loader.item) return
    var queue = pendingPayloads[pluginId]
    if (!Array.isArray(queue) || queue.length === 0) return
    if (typeof loader.item.open === "function") {
      for (var i = 0; i < queue.length; i++) {
        try { loader.item.open(queue[i]) } catch (e) {
          console.warn("plugin " + pluginId + " open() threw:", e)
        }
      }
    }
    pendingPayloads = Util.mapRemove(pendingPayloads, pluginId)
  }

  function invokeIfLoaded(pluginId, method, arg) {
    var loader = panelLoaders[pluginId]
    if (!loader || !loader.item) return
    if (typeof loader.item[method] !== "function") return
    try { loader.item[method](arg) } catch (e) {
      console.warn("plugin " + pluginId + " " + method + "() threw:", e)
    }
  }

  function callIfLoaded(pluginId, method, arg) {
    var id = shell.pluginRegistry.resolveEnabledId(pluginId)
    var loader = panelLoaders[id]
    if (!loader || !loader.item) return "unknown"
    if (typeof loader.item[method] !== "function") return "unknown"
    try {
      var result = loader.item[method](arg)
      return result === undefined || result === null ? "ok" : String(result)
    } catch (e) {
      console.warn("plugin " + id + " " + method + "() threw:", e)
      return "error"
    }
  }

  property var panelEntries: []

  function computePanelEntries() {
    var out = []
    var plugins = shell.pluginRegistry.installedPlugins
    var panelKinds = ["panel", "overlay", "menu"]
    for (var id in plugins) {
      var m = plugins[id]
      if (!m || !Array.isArray(m.kinds)) continue
      var matched = false
      for (var i = 0; i < panelKinds.length; i++)
        if (m.kinds.indexOf(panelKinds[i]) !== -1) { matched = true; break }
      if (!matched) continue
      if (!shell.pluginRegistry.isEnabled(id)) continue
      var kind = m.kinds.indexOf("panel") !== -1 ? "panel"
        : (m.kinds.indexOf("overlay") !== -1 ? "overlay" : "menu")
      out.push({ id: id, manifest: m, kind: kind, keepLoaded: m.keepLoaded === true })
    }
    return out
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { shell.panelEntries = shell.computePanelEntries() }
  }

  Instantiator {
    model: shell.panelEntries
    active: true

    delegate: QtObject {
      id: panelEntry
      required property var modelData
      readonly property string pluginId: modelData.id
      readonly property var manifest: modelData.manifest
      readonly property string entryKind: modelData.kind
      readonly property bool keepLoaded: modelData.keepLoaded === true
      readonly property string sourceUrl: shell.pluginRegistry.entryPointUrl(manifest, entryKind)

      property Loader panelLoader: Loader {
        source: panelEntry.sourceUrl
        active: panelEntry.sourceUrl !== "" && (panelEntry.keepLoaded || shell.openPanelIds[panelEntry.pluginId] === true)
        asynchronous: true
        onLoaded: {
          if (!item) return
          if ("shell" in item) item.shell = shell
          if ("manifest" in item) item.manifest = panelEntry.manifest
          if ("pluginRegistry" in item) item.pluginRegistry = shell.pluginRegistry
          if ("service" in item) item.service = shell.serviceFor(panelEntry.pluginId)
          shell.registerPanelLoader(panelEntry.pluginId, this)
        }
        onStatusChanged: {
          if (status === Loader.Error) {
            var detail = errorString && errorString() ? errorString() : ""
            if (!detail && sourceComponent) detail = sourceComponent.errorString()
            console.warn("panel plugin " + panelEntry.pluginId + " failed to load:", detail)
            shell.hide(panelEntry.pluginId)
          }
        }
        Component.onDestruction: shell.unregisterPanelLoader(panelEntry.pluginId)
      }
    }
  }

  // ---------------------------------------------------------- shell IPC

  IpcHandler {
    target: "shell"

    function ping(): string {
      return "ok"
    }

    function rescanPlugins(): void {
      shell.pluginRegistry.rescan()
    }

    function reloadConfig(): string {
      userConfigFile.reload()
      return "ok"
    }

    function setPluginEnabled(id: string, enabled: string): string {
      return shell.pluginRegistry.setEnabled(id, enabled === "true") ? "ok" : "unknown"
    }

    function enablePlugin(id: string, placementJson: string): string {
      try {
        var placement = JSON.parse(placementJson || "{}")
        if (shell.pluginRegistry.setEnabled(id, true, placement)) return "ok"
        return shell.pluginRegistry.lastEnableError || "unknown"
      } catch (e) {
        return "invalid placement: " + e
      }
    }

    // Enable, but only where the widget is not on the bar already, so a caller
    // that cannot know whether it ran before leaves a placed widget alone.
    function putBarWidget(id: string, placementJson: string): string {
      try {
        var error = shell.pluginRegistry.putBarWidget(id, JSON.parse(placementJson || "{}"))
        return error ? error : "ok"
      } catch (e) {
        return "invalid placement: " + e
      }
    }

    function moveBarWidget(id: string, placementJson: string): string {
      try {
        var error = shell.pluginRegistry.moveBarWidget(id, JSON.parse(placementJson || "{}"))
        return error ? error : "ok"
      } catch (e) {
        return "invalid placement: " + e
      }
    }

    function setBarWidget(id: string, key: string, valueJson: string, selectorJson: string): string {
      try {
        var value = JSON.parse(valueJson)
        var selector = JSON.parse(selectorJson || "{}")
        var error = shell.pluginRegistry.setBarWidget(id, key, value, selector)
        return error ? error : "ok"
      } catch (e) {
        return "invalid widget setting: " + e
      }
    }

    function listPlugins(): string {
      var out = []
      var plugins = shell.pluginRegistry.installedPlugins
      for (var id in plugins) {
        var kinds = plugins[id].kinds || []
        var isBarWidget = Array.isArray(kinds) && kinds.indexOf("bar-widget") !== -1
        out.push({
          id: id,
          name: plugins[id].name,
          kinds: kinds,
          enabled: isBarWidget ? shell.pluginRegistry.inBar(id) : shell.pluginRegistry.isEnabled(id),
          firstParty: !!plugins[id].__isFirstParty
        })
      }
      out.sort(function(left, right) {
        var leftName = String(left.name || left.id)
        var rightName = String(right.name || right.id)
        if (leftName < rightName) return -1
        if (leftName > rightName) return 1
        return String(left.id).localeCompare(String(right.id))
      })
      return JSON.stringify(out)
    }

    function listShellConfig(): string {
      return JSON.stringify(shell.shellConfig || {})
    }

    function summon(id: string, payloadJson: string): string {
      return shell.summon(id, payloadJson) ? "ok" : "unknown"
    }

    function hide(id: string): void {
      shell.hide(id)
    }

    function toggle(id: string, payloadJson: string): void {
      shell.toggle(id, payloadJson)
    }

    function call(id: string, method: string, arg: string): string {
      return shell.callIfLoaded(id, method, arg)
    }
  }

  // ------------------------------------------------- always-on components
  //
  // Mechanism 1 from this file's header: the desktop's own fixtures. Each is
  // unconditionally present and owns an IpcHandler that keybinds, scripts and
  // other widgets call into, so none of them has a meaningful disabled state
  // to model as a plugin. Startup fades itself out once login settles.
  Background {}
  Osd {}
  Clipboard {}
  AppSearch { appLibrary: shell.appLibrary }
  PowerMenu {}
  Overview {}
  Startup {}
}
