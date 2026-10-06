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
import "plugins/Plugins.js" as Plugins
import "services"

ShellRoot {
  id: shell

  // instances, relative-path imports do not share singleton state
  property AppLibrary appLibrary: AppLibrary { }

  // per-widget saved state, e.g. tray pins
  readonly property string widgetSettingsPath: Paths.state + "/widget-settings.json"

  property var widgetSettings: ({})

  function settingsForWidget(widgetId) {
    var entry = widgetSettings[String(widgetId)]
    return Util.isPlainObject(entry) ? entry : ({})
  }

  // true only if something changed
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
    printErrors: false
    onLoaded: {
      shell.applyWidgetSettings()
      // atomic writes replace the watched inode
      Util.rearmWatch(this)
    }
    onLoadFailed: shell.widgetSettings = ({})
    onFileChanged: reload()
  }

  readonly property string mainScreenName: {
    var screens = Quickshell.screens
    // a workspace rule may name the other machine's monitor
    function connected(name) {
      for (var s = 0; s < screens.length; s++) if (String(screens[s].name) === name) return true
      return false
    }
    var workspaces = Hyprland.workspaces.values
    for (var w = 0; w < workspaces.length; w++)
      if (workspaces[w].id === 1 && workspaces[w].monitor) return String(workspaces[w].monitor.name)
    // workspace 1 only exists while it has windows
    if (workspaceOneRuleMonitor && connected(workspaceOneRuleMonitor)) return workspaceOneRuleMonitor
    for (var i = 0; i < screens.length; i++)
      if (screens[i].x === 0 && screens[i].y === 0) return String(screens[i].name)
    return screens.length > 0 ? String(screens[0].name) : ""
  }

  property string workspaceOneRuleMonitor: ""

  Process {
    id: workspaceRulesProc
    command: ["hyprctl", "-j", "workspacerules"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = ""
        try {
          var rules = JSON.parse(text || "[]")
          for (var i = 0; i < rules.length; i++) {
            var ws = String(rules[i].workspaceString || "")
            if (ws === "1" && rules[i].monitor) { name = String(rules[i].monitor); break }
          }
        } catch (e) {
          console.warn("workspacerules parse failed:", e)
        }
        shell.workspaceOneRuleMonitor = name
      }
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
      // compared inside Bar: redeclaring modelData here breaks Variants
      mainScreenName: shell.mainScreenName
    }
  }

  // the Plugins.js shell table, each loaded once
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
    for (var i = 0; i < loaders.length; i++)
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

  // keybinds (hyprland_keybindings.lua) reach discord voice through here
  IpcHandler {
    target: "discord"

    function toggleMute(): bool { return DiscordControl.send("toggleSelfMute") }
    function toggleDeafen(): bool { return DiscordControl.send("toggleSelfDeaf") }
    function disconnect(): bool { return DiscordControl.send("disconnect") }
  }

  IpcHandler {
    target: "shell"

    // palette + fx for toggle-shader.sh
    function palette(): string {
      function rgb(c) { return [c.r, c.g, c.b] }
      return JSON.stringify({
        background: rgb(Color.background),
        accent: rgb(Color.accent),
        glowStrength: Style.fx.glow,
        scanlineOpacity: Style.fx.scanlineOpacity,
        scanlineSpacing: Style.fx.scanlineSpacing
      })
    }

    // toggle-powermode.sh, after saver flips
    function reloadPowerMode(): void {
      Power.reload()
    }

    function summon(id: string, payloadJson: string): string {
      return shell.summon(id, payloadJson) ? "ok" : "unknown"
    }
  }

  Background {}
  Osd {}
  Clipboard {}
  AppSearch { appLibrary: shell.appLibrary }
  PowerMenu {}
  Overview {}
  Lock {}
}