import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "display"

  property real brightnessPct: 50
  // false until a read answers, shown as "--" instead of a made-up 50
  property bool brightnessKnown: false
  // reads never fight a drag
  property bool brightnessDragging: false
  property var monitors: []
  readonly property var activeMonitors: monitors.filter(function (m) { return !m.disabled })

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refreshBrightnessFor(name) {
    var proc = brightnessGetComponent.createObject(root, { monitorName: name })
    proc.running = true
  }

  function refreshAllBrightness() {
    for (var i = 0; i < root.activeMonitors.length; i++)
      root.refreshBrightnessFor(root.activeMonitors[i].name)
  }

  function setBrightnessFor(name, pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    Quickshell.execDetached([Paths.script("monitor-brightness.sh"), "set", name, String(pct)])
  }

  function applyBrightnessAll(pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    root.brightnessPct = pct
    root.brightnessKnown = true
    for (var i = 0; i < root.activeMonitors.length; i++)
      root.setBrightnessFor(root.activeMonitors[i].name, pct)
  }

  function refreshMonitors() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  readonly property string gradingCli: Paths.dotfiles + "/configs/desktop/color-grading/color-grading.py"
  readonly property string shaderScript: Paths.toggle("toggle-shader.sh")
  property var grading: ({ preset: "", nightlight: false, presets: [] })
  property var shaders: ({ current: "off", shaders: [] })

  // panel opens re-read grading and shaders at most this often; actions re-read at once
  readonly property int colorMinAgeMs: 60 * 1000
  property real colorReadMs: 0

  function refreshColor() {
    root.colorReadMs = Date.now()
    if (!gradingProc.running) gradingProc.running = true
    if (!shaderProc.running) shaderProc.running = true
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
    id: colorActionProc
    onExited: root.refreshColor()
  }


  function setMonitorLayout(name, action) {
    var args = [Paths.toggle("toggle-monitor-scale.sh"), "layout", name]
    if (action.indexOf("mirror:") === 0) args.push("mirror", action.substring(7))
    else args.push(action)
    Quickshell.execDetached(args)
    monitorsSettle.restart()
  }

  // hyprland needs a moment before readback is current
  Timer {
    id: monitorsSettle
    interval: 800
    onTriggered: root.refreshMonitors()
  }

  function setMonitorScale(name, scale) {
    Quickshell.execDetached([Paths.toggle("toggle-monitor-scale.sh"), "live", String(scale), name])
    monitorsSettle.restart()
  }

  // one process per get so concurrent monitors don't clash
  Component {
    id: brightnessGetComponent
    Process {
      id: proc
      property string monitorName: ""
      command: [Paths.script("monitor-brightness.sh"), "get", monitorName]
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

  Timer {
    interval: 5000
    running: panel.visible
    repeat: true
    onTriggered: root.refreshMonitors()
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

    // keys and the osd change brightness behind the panel's back
    onOpened: {
      root.refreshMonitors()
      if (Date.now() - root.colorReadMs >= root.colorMinAgeMs) root.refreshColor()
      root.refreshAllBrightness()
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
              color: Color.menu.text
              opacity: Style.emphasis.dim
              font.pixelSize: Style.font.caption
              font.family: Style.font.family
              font.letterSpacing: Style.headerTracking * 0.4
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
            onActivated: root.colorRun([Paths.toggle("toggle-color-grading.sh"), "set", modelData.name])
          }
        }

        PanelRow {
          width: parent.width
          glyph: "\u{f0594}"
          on: root.grading.nightlight === true
          label: "Night light"
          onActivated: root.colorRun([Paths.toggle("toggle-nightlight.sh"), "toggle"])
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
              color: Color.menu.text
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
            Text {
              text: monitorRow.disabled ? "off"
                : monitorRow.modelData.width + "x" + monitorRow.modelData.height + "@" + Math.round(monitorRow.modelData.refreshRate) + "Hz"
                  + (monitorRow.mirrorOf ? "  |  mirroring " + monitorRow.mirrorOf : "")
              color: Color.menu.text
              opacity: Style.emphasis.dim
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
          }

          // no off on the last active output
          Flow {
            visible: root.monitors.length > 1
            width: parent.width
            spacing: Style.spacing.xs
            Repeater {
              model: {
                var opts = [{ value: "extend", label: "Extend" }]
                var others = 0
                for (var i = 0; i < root.monitors.length; i++) {
                  var m = root.monitors[i]
                  if (m.name === monitorRow.modelData.name || m.disabled) continue
                  if (m.mirrorOf && m.mirrorOf !== "none") continue
                  others++
                  opts.push({ value: "mirror:" + m.name, label: "Mirror " + m.name })
                }
                if (others > 0 || monitorRow.disabled) opts.push({ value: "off", label: "Off" })
                return opts
              }
              Chip {
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
                required property real modelData
                // hyprland reports 1.666667 as 1.6666666
                selected: Math.abs(Number(monitorRow.modelData.scale) - modelData) < 0.01
                text: (Math.round(modelData * 100) / 100) + "x"
                onClicked: root.setMonitorScale(monitorRow.modelData.name, modelData)
              }
            }
          }
        }
      }
    }
  }
}
