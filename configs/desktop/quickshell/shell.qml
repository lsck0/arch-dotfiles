pragma ComponentBehavior: Bound
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
    var next = Util.mapWithout(settings, "id")
    var current = widgetSettings[key]
    if (current && JSON.stringify(current) === JSON.stringify(next)) return false
    widgetSettings = Util.mapSet(widgetSettings, key, next)
    widgetSettingsFile.setText(JSON.stringify(widgetSettings, null, 2) + "\n")
    return true
  }

  WatchedFile {
    id: widgetSettingsFile
    path: shell.widgetSettingsPath
    atomicWrites: true
    onLoaded: shell.widgetSettings = Util.parseObject(text())
    onLoadFailed: shell.widgetSettings = ({})
  }

  readonly property string mainScreenName: {
    var one = Hyprland.workspaces.values.find(w => w.id === 1 && w.monitor)
    if (one) return String(one.monitor.name)
    if (workspaceOneRuleMonitor && Util.screenNamed(workspaceOneRuleMonitor)) return workspaceOneRuleMonitor
    var screens = Array.from(Quickshell.screens)
    var origin = screens.find(s => s.x === 0 && s.y === 0) || screens[0]
    return origin ? String(origin.name) : ""
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
      if (event.name !== "configreloaded") return
      workspaceRulesProc.running = true
      Style.gapsOutProc.running = true
    }
  }

  Component.onCompleted: workspaceRulesProc.running = true

  Variants {
    id: bars
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
      onItemChanged: if (item && "shell" in item) item.shell = shell // qmllint disable missing-property
    }
  }

  function barFor(screen) { return Array.from(bars.instances).find(b => b.screen === screen) || null }

  function plugin(id) {
    var loader = Array.from(plugins.instances).find(l => l.modelData === id)
    return loader ? loader.item : null
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
  DesktopWidgets { mainScreenName: shell.mainScreenName; shellHost: shell }
  Osd {}
  Clipboard {}
  AppSearch { appLibrary: shell.appLibrary }
  PowerMenu {}
  Overview {}
  Settings {}
  Lock { id: lockScreen; mainScreenName: shell.mainScreenName }
}
