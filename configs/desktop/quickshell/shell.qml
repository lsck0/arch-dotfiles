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
import "plugins/lock"
import "plugins/desktop"
import "plugins/settings"
import "plugins/Plugins.js" as Plugins
import "services"

ShellRoot {
  id: shell

  settings.watchFiles: !lockScreen.locked

  property AppLibrary appLibrary: AppLibrary { }

  readonly property string widgetSettingsPath: Paths.state + "/widget-settings.json"

  property var widgetSettings: ({})

  function settingsForWidget(widgetId) {
    var entry = widgetSettings[String(widgetId)]
    return Util.isPlainObject(entry) ? entry : ({})
  }

  function setWidgetSettings(widgetId, settings) {
    var key = String(widgetId)
    var next = {}
    for (let k in settings) if (k !== "id") next[k] = settings[k]
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
      let parsed = JSON.parse(text)
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
    printErrors: false
    onLoaded: {
      shell.applyWidgetSettings()
      Util.rearmWatch(this)
    }
    onLoadFailed: shell.widgetSettings = ({})
    onFileChanged: reload()
  }

  readonly property string mainScreenName: {
    var screens = Quickshell.screens
    function connected(name) {
      for (let s = 0; s < screens.length; s++) if (String(screens[s].name) === name) return true
      return false
    }
    var workspaces = Hyprland.workspaces.values
    for (let w = 0; w < workspaces.length; w++)
      if (workspaces[w].id === 1 && workspaces[w].monitor) return String(workspaces[w].monitor.name)
    if (workspaceOneRuleMonitor && connected(workspaceOneRuleMonitor)) return workspaceOneRuleMonitor
    for (let i = 0; i < screens.length; i++)
      if (screens[i].x === 0 && screens[i].y === 0) return String(screens[i].name)
    return screens.length > 0 ? String(screens[0].name) : ""
  }

  property string workspaceOneRuleMonitor: ""

  JsonProcess {
    id: workspaceRulesProc
    command: ["hyprctl", "-j", "workspacerules"]
    onParsed: function(rules) {
      var rule = (rules || []).find(r => String(r.workspaceString || "") === "1" && r.monitor)
      shell.workspaceOneRuleMonitor = rule ? String(rule.monitor) : ""
    }
    onFailed: function(error) {
      console.warn("workspacerules parse failed:", error)
      shell.workspaceOneRuleMonitor = ""
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") workspaceRulesProc.running = true
    }
  }

  Component.onCompleted: workspaceRulesProc.running = true

  Variants {
    model: Quickshell.screens

    Bar {
      shellHost: shell
      mainScreenName: shell.mainScreenName
    }
  }

  Variants {
    id: plugins
    model: Object.keys(Plugins.shell)

    LazyLoader {
      required property string modelData
      active: true
      source: Qt.resolvedUrl("plugins/" + Plugins.shell[modelData])
      onItemChanged: if (item && "shell" in item) item.shell = shell
    }
  }

  function plugin(id) {
    var loaders = plugins.instances
    for (let i = 0; i < loaders.length; i++)
      if (loaders[i].modelData === id) return loaders[i].item
    return null
  }

  function summon(id, payloadJson) {
    var item = plugin(id)
    if (!item || typeof item.open !== "function") {
      console.warn("summon: no plugin", id)
      return false
    }
    var payload
    try {
      payload = JSON.parse(payloadJson || "{}")
    } catch (e) {
      console.warn("summon: bad payload for", id, e)
      return false
    }
    item.open(payload)
    return true
  }

  IpcHandler {
    target: "discord"

    function toggleMute(): bool { return DiscordControl.send("toggleSelfMute") }
    function toggleDeafen(): bool { return DiscordControl.send("toggleSelfDeaf") }
    function disconnect(): bool { return DiscordControl.send("disconnect") }
  }

  IpcHandler {
    target: "shell"

    function palette(): string {
      function rgb(c) { return [c.r, c.g, c.b] }
      return JSON.stringify({
        background: rgb(Colors.background),
        surface: rgb(Colors.surface),
        foreground: rgb(Colors.foreground),
        muted: rgb(Colors.muted),
        accent: rgb(Colors.accent),
        accent2: rgb(Colors.accent2),
        urgent: rgb(Colors.urgent),
        warn: rgb(Colors.warn),
        ok: rgb(Colors.ok),
        glowStrength: Style.fx.glow,
        scanlineOpacity: Style.fx.scanlineOpacity,
        scanlineSpacing: Style.fx.scanlineSpacing
      })
    }

    function reloadPowerMode(): void {
      Power.reload()
    }

    function summon(id: string, payloadJson: string): string {
      return shell.summon(id, payloadJson) ? "ok" : "unknown"
    }
  }

  Background {}
  DesktopWidgets { mainScreenName: shell.mainScreenName }
  Osd {}
  Clipboard {}
  AppSearch { appLibrary: shell.appLibrary }
  PowerMenu {}
  Overview {}
  Settings {}
  Lock { id: lockScreen; mainScreenName: shell.mainScreenName }
}
