import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "display"

  property real brightnessPct: 50
  // seed once so later reads don't fight a drag
  property bool brightnessSeeded: false
  property var monitors: []
  readonly property var activeMonitors: monitors.filter(function (m) { return !m.disabled })
  property var fontChoices: []
  readonly property var fontSizes: [12, 13, 14, 16, 18]

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
    Quickshell.execDetached([Paths.shellScripts + "/monitor-brightness.sh", "set", name, String(pct)])
  }

  function applyBrightnessAll(pct) {
    pct = Math.max(1, Math.min(100, Math.round(pct)))
    root.brightnessPct = pct
    for (var i = 0; i < root.activeMonitors.length; i++)
      root.setBrightnessFor(root.activeMonitors[i].name, pct)
  }

  function refreshMonitors() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  function openWallpaperPicker() {
    // not switch-wallpaper.sh
    Quickshell.execDetached([Paths.shellScripts + "/wallpaper-picker.sh"])
  }

  function setFont(family) {
    Quickshell.execDetached([root.fontScript, "set", family])
    fontSettle.restart()
  }

  function setFontSize(size) {
    Quickshell.execDetached([root.fontScript, "set-size", String(size)])
    fontSettle.restart()
  }

  readonly property string fontScript: Paths.toggle("toggle-font.sh")

  readonly property string shaderScript: Paths.toggle("toggle-shader.sh")
  property string shaderState: "off"
  // an in-flight read may predate a change
  property bool shaderReadQueued: false

  function refreshShader() {
    if (shaderStateProc.running) root.shaderReadQueued = true
    else shaderStateProc.running = true
  }

  function setShader(name) {
    if (shaderSetProc.running) return
    shaderSetProc.command = [root.shaderScript, root.shaderState === name ? "off" : name]
    shaderSetProc.running = true
  }

  Process {
    id: shaderStateProc
    command: [root.shaderScript, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.shaderState = String(text || "").trim()
    }
    onExited: {
      if (!root.shaderReadQueued) return
      root.shaderReadQueued = false
      Qt.callLater(root.refreshShader)
    }
  }

  Process {
    id: shaderSetProc
    onExited: root.refreshShader()
  }

  // terminal font size, not quickshell's own base size
  property int currentFontSize: 0

  function refreshFontSize() {
    if (!fontSizeProc.running) fontSizeProc.running = true
  }

  Process {
    id: fontSizeProc
    command: [root.fontScript, "size"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text || "").trim(), 10)
        if (!isNaN(n)) root.currentFontSize = n
      }
    }
  }

  Process {
    id: fontListProc
    command: [root.fontScript, "shortlist"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var families = String(text || "").split("\n").filter(function (line) {
          return line.trim().length > 0
        })
        if (families.length > 0) root.fontChoices = families
      }
    }
  }

  // theme.json lands after the script's other writes
  Timer {
    id: fontSettle
    interval: 600
    onTriggered: root.refreshFontSize()
  }

  // action: extend, off, or mirror:<output>
  function setMonitorLayout(name, action) {
    var args = [Paths.shellScripts + "/set-monitor-layout.sh", name]
    if (action.indexOf("mirror:") === 0) args.push("mirror", action.substring(7))
    else args.push(action)
    Quickshell.execDetached(args)
    layoutSettleTimer.restart()
  }

  // hyprland needs a moment before readback is current
  Timer {
    id: layoutSettleTimer
    interval: 800
    onTriggered: root.refreshMonitors()
  }

  function setMonitorScale(name, scale) {
    Quickshell.execDetached([Paths.shellScripts + "/set-monitor-scale.sh", name, String(scale)])
    refreshMonitors()
  }

  // one process per get so concurrent monitors don't clash
  Component {
    id: brightnessGetComponent
    Process {
      id: proc
      property string monitorName: ""
      command: [Paths.shellScripts + "/monitor-brightness.sh", "get", monitorName]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var pct = parseInt(String(text || "").trim(), 10)
          if (!isNaN(pct) && !root.brightnessSeeded) {
            root.brightnessPct = pct
            root.brightnessSeeded = true
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
        if (!root.brightnessSeeded) root.refreshAllBrightness()
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
    fontListProc.running = true
    root.refreshFontSize()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍹"
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + titleInset + Style.shadowOffset

    // ddc/ci is slow, so read hardware only while open
    onOpened: {
      root.refreshMonitors()
      root.refreshAllBrightness()
      root.refreshFontSize()
      root.refreshShader()
    }

    title: "DISPLAY"

    component Hero: Row {
      property int pct: 0
      property color tint: Color.accent
      spacing: Style.spacing.xxs
      Text {
        id: heroNum
        anchors.bottom: parent.bottom
        text: parent.pct
        color: parent.tint
        font.family: Style.font.family
        font.pixelSize: Math.round(Style.font.display * 1.7)
        font.bold: true
        font.letterSpacing: Style.displayTracking
        layer.enabled: Style.fx.glow > 0
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Style.fx.glowColor
          shadowBlur: 1.0
          shadowVerticalOffset: 0
          shadowHorizontalOffset: 0
          blurMax: Style.fx.glowRadius
          autoPaddingEnabled: true
        }
      }
      Text {
        anchors.bottom: heroNum.bottom
        anchors.bottomMargin: Math.round(Style.font.display * 0.35)
        text: "%"
        color: parent.tint
        opacity: Style.emphasis.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.lg

      PanelSectionHeader { text: "BRIGHTNESS" }

      Column {
        width: parent.width
        spacing: Style.spacing.xs

        Item {
          width: parent.width
          implicitHeight: Math.max(briHero.implicitHeight, briReads.implicitHeight)
          height: implicitHeight
          Hero { id: briHero; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; pct: Math.round(root.brightnessPct) }
          Column {
            id: briReads
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.56
            spacing: Style.spacing.sm
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
            BarGauge { width: parent.width; height: Style.spacing.md; segments: 24; value: root.brightnessPct / 100 }
          }
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 1
          maximum: 100
          integer: true
          value: root.brightnessPct
          onMoved: function(v) { root.brightnessPct = v }
          onReleased: function(v) { root.applyBrightnessAll(v) }
        }
      }

      PanelSectionHeader { text: "WALLPAPER" }

      PanelRow {
        width: parent.width
        glyph: "\u{f02e9}"
        label: "Choose wallpaper..."
        onActivated: { root.openWallpaperPicker(); if (root.bar) root.bar.closePanel(root.moduleName) }
      }

      PanelSectionHeader { text: "SHADER" }

      Repeater {
        model: [
          { name: "nightlight", label: "Night light" },
          { name: "color-grading", label: "Color grading" },
          { name: "cyberpunk", label: "Cyberpunk" }
        ]
        PanelRow {
          required property var modelData
          width: parent.width
          stateMarker: true
          on: root.shaderState === modelData.name
          label: modelData.label
          onActivated: root.setShader(modelData.name)
        }
      }

      PanelSectionHeader { text: "FONT" }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.fontChoices
          Chip {
            required property string modelData
            text: modelData
            selected: Style.fontFamily === modelData
            onClicked: root.setFont(modelData)
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        Repeater {
          model: root.fontSizes
          Chip {
            required property int modelData
            text: String(modelData)
            selected: root.currentFontSize === modelData
            onClicked: root.setFontSize(modelData)
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
          spacing: Style.spacing.sm

          readonly property bool disabled: !!modelData.disabled
          readonly property string mirrorOf: modelData.mirrorOf && modelData.mirrorOf !== "none" ? modelData.mirrorOf : ""
          readonly property string layoutValue: disabled ? "off" : (mirrorOf ? "mirror:" + mirrorOf : "extend")

          Row {
            spacing: Style.spacing.md
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
            spacing: Style.spacing.sm
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
            spacing: Style.spacing.sm
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
