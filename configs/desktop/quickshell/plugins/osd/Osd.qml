import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "OsdModel.js" as OsdModel

Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200
  // log mode: typed lines instead of icon and gauge
  property var lines: []
  property int typedChars: 0
  readonly property bool logMode: lines.length > 0
  readonly property int logChars: lines.join("").length
  readonly property int typeStepMs: 12
  readonly property int logDurationMs: 2400

  readonly property int pad: Style.space(16)
  readonly property int gap: Style.space(16)
  readonly property int messageGap: Math.round(root.gap * 2 / 3)
  readonly property int barWidth: Style.space(142)
  readonly property int maxMessageWidth: Style.space(190)
  readonly property int borderWidth: Math.max(1, Style.space(2))

  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int iconWidth: root.hasProgress
    ? Math.max(root.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width))
    : root.iconInkWidth
  readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, messageMetrics.advanceWidth))
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int logWidth: Math.ceil(logMetrics.advanceWidth)
  readonly property int contentWidth: root.logMode ? root.logWidth : root.hasProgress
    ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth)

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    lines = []
    opened = true
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  // a short typed log, one char per typeStepMs across the lines
  function log(logLines, rawDuration) {
    lines = (logLines || []).map(function(l) { return String(l) })
    typedChars = Style.motion.enabled ? 0 : logChars
    duration = rawDuration === undefined ? logDurationMs : Math.max(0, Number(rawDuration) || 0)
    opened = true
    if (typedChars < logChars) typer.restart()
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  // the visible part of line i while typing
  function typedLine(i) {
    var before = 0
    for (var k = 0; k < i; k++) before += lines[k].length
    return lines[i].substring(0, Math.max(0, typedChars - before))
  }

  function hex(c) { return String(c).substring(0, 7) }

  // palette sync (signature D): Color applies a new wallpaper palette
  Connections {
    target: Color
    function onPaletteSynced(p) {
      root.log(["> SYNC PALETTE", "  bg " + root.hex(p.background) + " :: acc " + root.hex(p.accent), "  " + p.verdict])
    }
  }

  Timer {
    id: typer
    interval: root.typeStepMs
    repeat: true
    onTriggered: {
      root.typedChars++
      if (root.typedChars >= root.logChars) stop()
    }
  }

  BootIn { id: boot; active: root.opened }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (Array.isArray(p.lines)) {
        root.log(p.lines, p.duration)
        return
      }
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    } catch (e) {}
  }

  function close() { opened = false }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
  }

  TextMetrics {
    id: logMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    text: root.lines.reduce(function(a, b) { return b.length > a.length ? b : a }, "")
  }

  TextMetrics {
    id: valueMetrics
    font: messageMetrics.font
    text: "100%"
  }

  TextMetrics {
    id: iconMetrics
    // drawn texts reuse this font via iconMetrics.font
    font.family: Style.font.iconFamily
    font.pixelSize: Style.font.displayLarge
    text: root.icon
  }

  TextMetrics {
    id: widestIconMetrics
    font: iconMetrics.font
    text: OsdModel.widestIcon
  }

  IpcHandler {
    target: "osd"
    // not show: qs ipc parses show as its own subcommand
    function present(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // one surface per output, only the focused one visible
  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData

      readonly property bool onFocusedMonitor: {
        var mine = Hyprland.monitorFor(modelData)
        var focused = Hyprland.focusedMonitor
        // no focused monitor yet: show rather than swallow
        if (!mine || !focused) return true
        return mine.name === focused.name
      }

      // mapped until the fade-out ends
      visible: (root.opened || boot.progress > 0) && onFocusedMonitor
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "quickshell-osd"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Rectangle {
        id: card
        readonly property int logHeight: root.lines.length * Math.ceil(logMetrics.height)
        width: root.borderWidth * 2 + root.pad * 2 + root.contentWidth
        height: root.borderWidth * 2 + root.pad * 2 + (root.logMode ? logHeight : Style.font.displayLarge)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(67)
        color: Color.menu.background
        border.width: root.borderWidth
        border.color: Color.popups.border
        radius: Style.shape.surface
        opacity: boot.progress
        transform: Translate { y: (1 - boot.progress) * Style.spacing.sm }

        Column {
          visible: root.logMode
          anchors.fill: parent
          anchors.margins: card.border.width + root.pad

          Repeater {
            model: root.lines.length
            Text {
              required property int index
              textFormat: Text.PlainText
              text: root.typedLine(index)
              color: index === 0 ? Color.accent : Color.popups.text
              font: logMetrics.font
            }
          }
        }

        Row {
          visible: !root.logMode
          anchors.fill: parent
          anchors.margins: card.border.width + root.pad
          spacing: root.hasProgress ? root.gap : root.messageGap

          Item {
            width: root.iconWidth
            height: parent.height
            Text {
              textFormat: Text.PlainText
              x: Math.round((root.iconWidth - root.iconInkWidth) / 2 - iconMetrics.tightBoundingRect.x)
              anchors.verticalCenter: parent.verticalCenter
              text: root.icon
              font: iconMetrics.font
              color: Color.popups.text
            }
          }
          BarGauge {
            visible: root.hasProgress
            anchors.verticalCenter: parent.verticalCenter
            width: root.barWidth
            height: Math.max(Style.space(6), Style.spacing.xs)
            segments: 20
            value: root.maxValue > 0 ? root.value / root.maxValue : 0
            color: Color.accent
          }
          Text {
            textFormat: Text.PlainText
            visible: root.message !== ""
            width: root.hasProgress ? root.valueWidth : root.messageWidth
            horizontalAlignment: root.hasProgress ? Text.AlignRight : Text.AlignLeft
            anchors.verticalCenter: parent.verticalCenter
            text: root.message
            font: messageMetrics.font
            color: Color.popups.text
            elide: Text.ElideRight
            maximumLineCount: 1
            // changes on every key repeat: outline, never a MultiEffect
            style: Style.fx.glow > 0 ? Text.Outline : Text.Normal
            styleColor: Util.alpha(Color.accent, 0.35)
          }
        }

        HudFrame {}
        Scanlines {}
      }
    }
  }
}
