import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "OsdModel.js" as OsdModel

// Adapted from omarchy-shell's Osd.qml: same measured-column layout and IPC
// contract (`quickshell ipc -p ~/.config/quickshell call osd present '{...}'`), with
// BorderSurface's multi-side/gradient border swapped for a plain Rectangle
// border — this repo doesn't need per-side gradient borders, just a card.
Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200

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
  readonly property int contentWidth: root.hasProgress
    ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth)

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    opened = true
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
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
    id: valueMetrics
    font: messageMetrics.font
    text: "100%"
  }

  TextMetrics {
    id: iconMetrics
    // Icon family: root.icon is always a Nerd Font glyph, and the drawn
    // Text elements below inherit this via `font: iconMetrics.font`, so
    // this one line covers both the metrics and the rendering.
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
    // NOT named `show`. `quickshell ipc` has its own `show` subcommand (it
    // lists every IPC target), so an IpcHandler function called `show`
    // cannot be invoked from the CLI at all: the parser binds `show` as a
    // command and then rejects the payload with
    // "show: The following argument was not expected: {...}".
    // `call osd close` works fine, which is why the collision hid for so
    // long — and it meant AppLibrary's launch OSD had never actually
    // fired. `show` is kept as an alias for the no-argument case.
    function present(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function show(): string {
      root.open("{}")
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // One surface per output, but only the FOCUSED one is ever visible.
  //
  // This used to be `visible: root.opened` on every screen at once, so a
  // volume or brightness OSD popped up simultaneously on every monitor —
  // fine on a single-output laptop, which is why it went unnoticed, but
  // wrong the moment a second display is plugged in.
  //
  // Variants is kept rather than creating one window on the focused screen,
  // because a PanelWindow that changes `screen` at runtime has to tear down
  // and rebuild its wayland surface; toggling `visible` on pre-built
  // surfaces is cheaper and avoids a flicker when focus moves mid-OSD.
  //
  // `Hyprland.monitorFor(screen)` is the bridge between a Quickshell screen
  // and Hyprland's own monitor object; comparing against
  // `Hyprland.focusedMonitor` is what makes "focused" mean what the
  // compositor thinks it means, not what Qt guesses.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: osdWindow
      required property var modelData
      screen: modelData

      readonly property bool onFocusedMonitor: {
        var mine = Hyprland.monitorFor(modelData)
        var focused = Hyprland.focusedMonitor
        // Before Hyprland has reported a focused monitor, fall back to
        // showing it rather than swallowing the OSD entirely.
        if (!mine || !focused) return true
        return mine.name === focused.name
      }

      visible: root.opened && onFocusedMonitor
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "quickshell-osd"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Rectangle {
        id: card
        width: root.borderWidth * 2 + root.pad * 2 + root.contentWidth
        height: root.borderWidth * 2 + root.pad * 2 + Style.font.displayLarge
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(67)
        color: Util.alpha(Color.background, 0.97)
        border.width: root.borderWidth
        border.color: Color.popups.border
        radius: Style.cornerRadius
        opacity: root.opened ? 1 : 0

        Row {
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
          Rectangle {
            visible: root.hasProgress
            width: root.barWidth
            height: Math.max(Style.space(6), Style.spacing.sm)
            anchors.verticalCenter: parent.verticalCenter
            color: Util.alpha(Color.popups.text, 0.45)
            Rectangle {
              height: parent.height
              width: parent.width * (root.hasProgress ? root.value / root.maxValue : 0)
              color: Color.accent

              Behavior on width {
                enabled: root.opened
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }
            }
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
          }
        }
      }
    }
  }
}
