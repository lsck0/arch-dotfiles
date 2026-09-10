import QtQuick
import Quickshell
import Quickshell.Io
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
ShellRoot {
  id: shell

  // Shared service instances, injected into Bar via property (relative-path
  // imports don't share singleton state across importers, so these are
  // regular instances built once here and handed down).
  property PluginRegistry pluginRegistry: PluginRegistry { }
  property BarWidgetRegistry barWidgetRegistry: BarWidgetRegistry { }
  property AppLibrary appLibrary: AppLibrary { }
  Startup { }

  // Startup overlay is independent of the bar and fades after login settles.

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
        left: [{ id: "bar.app-menu" }, { id: "bar.workspaces" }],
        // SPEC puts datetime and media in the middle; weather was a later
        // addition to the same spec and rides along here. Media moved out of
        // `right` 2026-09-02 once panel anchoring could put a centre widget's
        // panel under its own trigger (Phase 2a).
        center: [{ id: "bar.clock" }, { id: "bar.weather" }, { id: "bar.media" }],
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
          { id: "bar.tray" },
          { id: "bar.system" },
          { id: "bar.network" }, { id: "bar.display" }, { id: "bar.audio-io" },
          { id: "bar.notifications" },
          { id: "bar.keyboard-layout" },
          { id: "bar.indicators" }
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

  // Writes inline settings to a bar layout entry or top-level plugin entry
  // in shell.json. moduleName is the entry id; settings is the merged
  // plugin state (e.g. Tray's pinned/hidden item id lists). Returns true
  // if anything actually changed — added for Phase 3's Tray widget, which
  // needs this to persist pin/hide state; missed in the initial Phase 2
  // port since nothing needed it yet.
  function updateEntryInline(moduleName, settings) {
    var stripped = Util.canonicalWidgetId(moduleName)
    var copy = Util.cloneJson(shellConfig || builtinShellConfig)
    if (!Util.isPlainObject(copy.bar)) copy.bar = { layout: { left: [], center: [], right: [] } }
    if (!Util.isPlainObject(copy.bar.layout)) copy.bar.layout = { left: [], center: [], right: [] }
    if (!Array.isArray(copy.plugins)) copy.plugins = []

    var sections = ["left", "center", "right"]
    var foundInLayout = false
    var dirty = false
    for (var s = 0; s < sections.length; s++) {
      var arr = copy.bar.layout[sections[s]] || []
      for (var i = 0; i < arr.length; i++) {
        if (arr[i] && Util.canonicalWidgetId(arr[i].id) === stripped) {
          var next = { id: stripped }
          for (var k in settings) if (k !== "id") next[k] = settings[k]
          if (JSON.stringify(arr[i]) !== JSON.stringify(next)) {
            arr[i] = next
            dirty = true
          }
          foundInLayout = true
        }
      }
    }
    if (!foundInLayout) {
      for (var j = 0; j < copy.plugins.length; j++) {
        if (copy.plugins[j] && copy.plugins[j].id === stripped) {
          var pnext = { id: stripped }
          for (var pk in settings) if (pk !== "id") pnext[pk] = settings[pk]
          if (JSON.stringify(copy.plugins[j]) !== JSON.stringify(pnext)) {
            copy.plugins[j] = pnext
            dirty = true
          }
        }
      }
    }
    if (!dirty) return false
    persistShellConfig(copy)
    return true
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
  // wins; otherwise the output positioned at the origin, which is how this
  // setup pins its desktop display. Falls back to the first screen so a
  // machine whose outputs are all offset still gets exactly one full bar
  // rather than none.
  readonly property string mainScreenName: {
    var configured = barConfig && barConfig.mainScreen ? String(barConfig.mainScreen) : ""
    if (configured) return configured
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
      barWidgetRegistry: shell.barWidgetRegistry
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
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = shell.barWidgetRegistry
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
          if ("barWidgetRegistry" in item) item.barWidgetRegistry = shell.barWidgetRegistry
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

  // ---------------------------------------------------------- plugin loader
  //
  // Mirrors plugin registry state into BarWidgetRegistry whenever it changes.
  // Each enabled plugin with kind "bar-widget" gets a Component created from
  // its manifest entry point and registered under its manifest id.

  property var pluginWidgetComponents: ({})

  function syncPluginWidgets() {
    var plugins = shell.pluginRegistry.installedPlugins
    var seen = ({})

    for (var pluginId in plugins) {
      var manifest = plugins[pluginId]
      if (!manifest || !manifest.kinds || manifest.kinds.indexOf("bar-widget") === -1) continue
      if (!shell.pluginRegistry.isEnabled(pluginId)) continue

      var registryKey = String(manifest.id)
      seen[registryKey] = true

      var existing = pluginWidgetComponents[registryKey]
      var url = shell.pluginRegistry.entryPointUrl(manifest, "barWidget")
      if (!url) {
        console.warn("Plugin " + manifest.id + " has no barWidget entry point")
        continue
      }
      var meta = manifest.barWidget || {}
      meta = {
        displayName: meta.displayName || manifest.name,
        description: meta.description || manifest.description,
        category: meta.category || "Plugin",
        allowMultiple: meta.allowMultiple === true,
        defaultSection: meta.defaultSection || "center",
        pluginId: manifest.id,
        sourceDir: manifest.__sourceDir || "",
        source: manifest.__isFirstParty ? "first-party" : "plugin"
      }

      if (existing && existing.url === url && !existing.component) continue

      if (existing && existing.url === url && shell.barWidgetRegistry.has(registryKey)) {
        shell.barWidgetRegistry.register(registryKey, existing.component, meta)
        continue
      }

      loadPluginWidget(registryKey, url, meta)
    }

    var allIds = shell.barWidgetRegistry.availableIds()
    for (var i = 0; i < allIds.length; i++) {
      var id = allIds[i]
      if (!pluginWidgetComponents[id]) continue
      if (!seen[id]) {
        shell.barWidgetRegistry.unregister(id)
        pluginWidgetComponents = Util.mapRemove(pluginWidgetComponents, id)
      }
    }
  }

  Connections {
    target: shell.pluginRegistry
    function onPluginsChanged() { shell.syncPluginWidgets() }
  }

  function setPluginWidgetComponent(registryKey, entry) {
    pluginWidgetComponents = entry
      ? Util.mapSet(pluginWidgetComponents, registryKey, entry)
      : Util.mapRemove(pluginWidgetComponents, registryKey)
  }

  function loadPluginWidget(registryKey, url, meta) {
    setPluginWidgetComponent(registryKey, { url: url, component: null })

    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Ready) {
        shell.barWidgetRegistry.register(registryKey, comp, meta)
        shell.setPluginWidgetComponent(registryKey, { url: url, component: comp })
      } else if (comp.status === Component.Error) {
        console.warn("Plugin widget " + registryKey + " failed: " + comp.errorString())
        shell.setPluginWidgetComponent(registryKey, null)
        shell.pluginRegistry.pluginLoadFailed(registryKey, comp.errorString())
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
    } else {
      finalize()
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

  Background {}
  Osd {}
  Clipboard {}
  AppSearch { appLibrary: shell.appLibrary }
  PowerMenu {}
  Overview {}
}
