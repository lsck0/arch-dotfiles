pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "display"

  property real brightnessPct: 50
  property bool brightnessKnown: false
  property bool brightnessDragging: false
  property var monitors: []
  readonly property var activeMonitors: monitors.filter(function (m) { return !m.disabled })

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refreshBrightnessFor(name) {
    const proc = brightnessGetComponent.createObject(root, { monitorName: name }) as Process
    proc.running = true
  }

  function refreshAllBrightness() {
    for (let i = 0; i < root.activeMonitors.length; i++)
      root.refreshBrightnessFor(root.activeMonitors[i].name)
  }

  function setBrightnessFor(name, pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    Quickshell.execDetached([Paths.script("monitor-brightness.nu"), "set", name, String(pct)])
  }

  function applyBrightnessAll(pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    root.brightnessPct = pct
    root.brightnessKnown = true
    for (let i = 0; i < root.activeMonitors.length; i++)
      root.setBrightnessFor(root.activeMonitors[i].name, pct)
  }

  function refreshMonitors() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  readonly property string gradingCli: Paths.dotfiles + "/configs/desktop/color-grading/color-grading.py"
  readonly property string shaderScript: Paths.toggle("toggle-shader.nu")
  property var grading: ({ preset: "", nightlight: false, presets: [] })
  property var shaders: ({ current: "off", shaders: [] })
  readonly property string themeModeScript: Paths.toggle("toggle-theme-mode.nu")
  property string themeMode: "dark"
  property string themePartner: ""

  readonly property int colorMinAgeMs: 60 * 1000
  property real colorReadMs: 0

  function refreshColor() {
    root.colorReadMs = Date.now()
    if (!gradingProc.running) gradingProc.running = true
    if (!shaderProc.running) shaderProc.running = true
    root.refreshTheme()
  }

  function refreshTheme() {
    if (!themeModeProc.running) themeModeProc.running = true
    if (!themeTargetProc.running) themeTargetProc.running = true
  }

  function colorRun(argv) {
    if (colorActionProc.running) return
    colorActionProc.command = argv
    colorActionProc.running = true
  }

  function shaderName(entry) { return String(entry).split(":")[0] }
  function shaderVariant(entry) { var i = String(entry).indexOf(":"); return i < 0 ? "" : String(entry).substring(i + 1) }

  Process {
    id: gradingProc
    command: [root.gradingCli, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.grading = JSON.parse(text || "{}") } catch (e) {} }
    }
  }

  Process {
    id: shaderProc
    command: [root.shaderScript, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.shaders = JSON.parse(text || "{}") } catch (e) {} }
    }
  }

  Process {
    id: themeModeProc
    command: [root.themeModeScript, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { var mode = String(text || "").trim(); if (mode !== "") root.themeMode = mode }
    }
  }

  // the theme the light/dark flip lands on, so the row says where it goes
  Process {
    id: themeTargetProc
    command: [root.themeModeScript, "target"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.themePartner = JSON.parse(text || "{}").theme || "" } catch (e) { root.themePartner = "" } }
    }
  }

  Connections {
    target: ToggleEvents
    function onChanged(script) { if (script === "toggle-theme-mode.nu") root.refreshTheme() }
  }

  Process {
    id: colorActionProc
    onExited: root.refreshColor()
  }

  function setMonitorLayout(name, action) {
    var args = [Paths.toggle("toggle-monitor-scale.nu"), "layout", name]
    if (action.indexOf("mirror:") === 0) args.push("mirror", action.substring(7))
    else args.push(action)
    Quickshell.execDetached(args)
    monitorsSettle.restart()
  }

  Timer {
    id: monitorsSettle
    interval: 800
    onTriggered: root.refreshMonitors()
  }

  function setMonitorScale(name, scale) {
    Quickshell.execDetached([Paths.toggle("toggle-monitor-scale.nu"), "live", String(scale), name])
    monitorsSettle.restart()
  }

  Component {
    id: brightnessGetComponent
    Process {
      id: proc
      property string monitorName: ""
      command: [Paths.script("monitor-brightness.nu"), "get", monitorName]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var pct = parseInt(String(text || "").trim(), 10)
          if (!isNaN(pct) && !root.brightnessDragging) {
            root.brightnessPct = pct
            root.brightnessKnown = true
          }
          proc.destroy()
        }
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.monitors = JSON.parse(text || "[]")
        } catch (e) {
          return
        }
        if (!root.brightnessKnown) root.refreshAllBrightness()
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "monitoradded" || event.name === "monitorremoved") root.refreshMonitors()
    }
  }

  Component.onCompleted: {
    root.refreshMonitors()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{f0379}"
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    onOpened: {
      root.refreshMonitors()
      if (Date.now() - root.colorReadMs >= root.colorMinAgeMs) root.refreshColor()
      root.refreshAllBrightness()
      root.refreshTheme()
    }

    title: "DISPLAY"

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      PanelSectionHeader { text: "BRIGHTNESS" }

      Column {
        width: parent.width
        spacing: Style.spacing.xs

        Item {
          width: parent.width
          implicitHeight: Math.max(briHero.implicitHeight, briReads.implicitHeight)
          height: implicitHeight
          Hero { id: briHero; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; value: root.brightnessKnown ? String(Math.round(root.brightnessPct)) : "--"; unit: "%" }
          Column {
            id: briReads
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.56
            spacing: Style.spacing.xs
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignRight
              text: root.activeMonitors.length > 1 ? root.activeMonitors.length + " MONITORS" : "1 MONITOR"
              color: Colors.menu.text
              opacity: Style.emphasis.dim
              font.pixelSize: Style.font.caption
              font.family: Style.font.family
              font.letterSpacing: Style.labelTracking
            }
            BarGauge { width: parent.width; height: Style.spacing.sm; segments: 24; value: root.brightnessPct / 100 }
          }
        }

        Slider {
          width: parent.width
          bar: root.bar
          minimum: 1
          maximum: 100
          integer: true
          value: root.brightnessPct
          onMoved: function(v) { root.brightnessDragging = true; root.brightnessPct = v }
          onReleased: function(v) { root.brightnessDragging = false; root.applyBrightnessAll(v) }
        }
      }

      PanelSectionHeader { text: "MONITORS" }

      Repeater {
        model: root.monitors
        Column {
          id: monitorRow
          required property var modelData
          width: content.width
          spacing: Style.spacing.xs

          readonly property bool disabled: !!modelData.disabled
          readonly property string mirrorOf: modelData.mirrorOf && modelData.mirrorOf !== "none" ? modelData.mirrorOf : ""
          readonly property string layoutValue: disabled ? "off" : (mirrorOf ? "mirror:" + mirrorOf : "extend")

          Row {
            spacing: Style.spacing.sm
            Text {
              text: monitorRow.modelData.name
              color: Colors.menu.text
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
            Text {
              text: monitorRow.disabled ? "off"
                : monitorRow.modelData.width + "x" + monitorRow.modelData.height + "@" + Math.round(monitorRow.modelData.refreshRate) + "Hz"
                  + (monitorRow.mirrorOf ? "  |  mirroring " + monitorRow.mirrorOf : "")
              color: Colors.menu.text
              opacity: Style.emphasis.dim
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
          }

          Flow {
            visible: root.monitors.length > 1
            width: parent.width
            spacing: Style.spacing.xs
            Repeater {
              model: {
                var opts = [{ value: "extend", label: "Extend" }]
                var others = 0
                for (let i = 0; i < root.monitors.length; i++) {
                  const m = root.monitors[i]
                  if (m.name === monitorRow.modelData.name || m.disabled) continue
                  if (m.mirrorOf && m.mirrorOf !== "none") continue
                  others++
                  opts.push({ value: "mirror:" + m.name, label: "Mirror " + m.name })
                }
                if (others > 0 || monitorRow.disabled) opts.push({ value: "off", label: "Off" })
                return opts
              }
              Chip {
                focusable: true
                required property var modelData
                text: modelData.label
                selected: modelData.value === monitorRow.layoutValue
                onClicked: if (!selected) root.setMonitorLayout(monitorRow.modelData.name, modelData.value)
              }
            }
          }

          Flow {
            visible: !monitorRow.disabled
            width: parent.width
            spacing: Style.spacing.xs
            Repeater {
              model: [1, 1.25, 1.5, 1.666667, 2]
              Chip {
                focusable: true
                required property real modelData
                selected: Math.abs(Number(monitorRow.modelData.scale) - modelData) < 0.01
                text: (Math.round(modelData * 100) / 100) + "x"
                onClicked: root.setMonitorScale(monitorRow.modelData.name, modelData)
              }
            }
          }
        }
      }

      PanelSectionHeader { text: "THEME" }

      PanelRow {
        width: parent.width
        glyph: "\u{f050e}"   // md-theme_light_dark
        on: root.themeMode === "light"
        label: "Light mode" + (root.themePartner !== "" ? " :: " + root.themePartner : "")
        onActivated: Quickshell.execDetached([root.themeModeScript, "toggle"])
      }

      PanelRow {
        width: parent.width
        glyph: "\u{f02e9}"   // md-image
        label: "Pick wallpaper"
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached([Paths.script("wallpaper-picker.nu")])
        }
      }

      PanelRow {
        width: parent.width
        glyph: "\u{f049d}"   // md-shuffle_variant
        label: "Random theme"
        onActivated: Quickshell.execDetached([Paths.dotfiles + "/scripts/dot.nu", "theme", "random"])
      }

      PanelSectionHeader { text: "COLOR GRADING" }

      Column {
        width: parent.width
        spacing: Style.spacing.xxs

        Repeater {
          model: root.grading.presets || []
          PanelRow {
            required property var modelData
            width: parent.width
            stateMarker: true
            on: root.grading.preset === modelData.name
            label: modelData.label
            onActivated: root.colorRun([Paths.toggle("toggle-color-grading.nu"), "set", modelData.name])
          }
        }

        PanelRow {
          width: parent.width
          on: root.grading.nightlight === true
          label: "Night light"
          onActivated: root.colorRun([Paths.toggle("toggle-nightlight.nu"), "toggle"])
        }
      }

      PanelSectionHeader { text: "SHADERS" }

      Column {
        width: parent.width
        spacing: Style.spacing.xxs

        PanelRow {
          width: parent.width
          stateMarker: true
          on: root.shaders.current === "off"
          label: "Off"
          onActivated: root.colorRun([root.shaderScript, "off"])
        }

        Repeater {
          model: root.shaders.shaders || []
          Column {
            id: shaderItem
            required property var modelData
            readonly property bool active: root.shaderName(root.shaders.current) === modelData.name
            width: parent.width
            spacing: Style.spacing.xxs

            PanelRow {
              width: parent.width
              stateMarker: true
              on: shaderItem.active
              label: shaderItem.modelData.label
              onActivated: root.colorRun([root.shaderScript, shaderItem.active ? "off" : "set", shaderItem.modelData.name])
            }

            ButtonGroup {
              visible: shaderItem.modelData.variants.length > 0
              width: parent.width
              fill: true
              spacing: Style.spacing.xs
              fontSize: Style.font.caption
              options: shaderItem.modelData.variants.map(function(v) { return { value: v, label: v.toUpperCase() } })
              value: shaderItem.active ? root.shaderVariant(root.shaders.current) : ""
              onChanged: function(v) { root.colorRun([root.shaderScript, "set", shaderItem.modelData.name + ":" + v]) }
            }
          }
        }
      }
    }
  }
}
