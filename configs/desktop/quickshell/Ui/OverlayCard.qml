import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
  id: root

  property bool open: false
  property string name: "overlay"
  property string title: ""
  property string suffix: ""
  property bool prompt: false
  property string query: ""
  property string placeholder: ""
  property var hints: []
  property real cardWidth: Style.space(560)
  property real cardHeight: Style.space(480)
  property bool scanlines: true
  property bool keyboard: true

  signal dismissed()

  default property alias content: body.data
  readonly property alias card: card
  readonly property alias boot: bootIn
  readonly property real contentWidth: body.width
  readonly property real contentHeight: body.height

  readonly property real inset: Style.surface.borderWidth + Style.surface.padding
  readonly property real promptHeight: Style.font.heading + Style.spacing.controlPaddingY * 2
  readonly property real chromeWidth: inset * 2
  readonly property real chromeHeight: inset * 2 + titleBar.implicitHeight + chrome.spacing
    + (root.prompt ? root.promptHeight + chrome.spacing : 0)
    + (root.hints.length > 0 ? footer.implicitHeight + chrome.spacing : 0)

  visible: open || bootIn.progress > 0
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "quickshell-" + root.name
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.open && root.keyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  BootIn {
    id: bootIn
    active: root.open
    title: root.title
    span: Math.min(card.width, card.height) / 2
  }

  Rectangle {
    anchors.fill: parent
    color: Colors.scrim
    opacity: bootIn.progress
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.open
    onClicked: root.dismissed()
  }

  Item {
    id: card
    anchors.centerIn: parent
    width: Math.min(root.cardWidth, root.width - Style.gapsOut * 2)
    height: Math.min(root.cardHeight, root.height - Style.gapsOut * 2)
    opacity: bootIn.progress

    MouseArea { anchors.fill: parent }

    DockShape {
      id: shape
      anchors.fill: parent
      fillColor: Colors.overlayFill
      glow: true
    }

    Column {
      id: chrome
      x: root.inset
      y: root.inset
      width: card.width - root.inset * 2
      height: card.height - root.inset * 2
      spacing: Style.spacing.sm

      HudTitle {
        id: titleBar
        width: parent.width
        text: root.title
        suffix: root.suffix
        typed: bootIn.typed
        size: Style.font.title
        decor: true
        rule: true
        blinking: root.open
      }

      Item {
        id: promptLine
        visible: root.prompt
        width: parent.width
        height: root.promptHeight

        Row {
          id: promptRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Text {
            id: promptGlyph
            textFormat: Text.PlainText
            text: ">"
            color: Colors.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: Math.min(implicitWidth, promptRow.width - promptGlyph.width - caret.width - promptRow.spacing * 2)
            text: root.query || root.placeholder
            color: Colors.menu.text
            opacity: root.query ? 1 : Style.emphasis.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          BlinkCaret { id: caret; size: Style.font.heading; prompt: true; running: root.open && root.prompt }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.spacing.xxs
          color: Util.alpha(Colors.accent, Style.surface.ruleAlpha)
        }
      }

      Item {
        id: body
        width: parent.width
        height: Math.max(0, chrome.height - titleBar.height - chrome.spacing
          - (promptLine.visible ? promptLine.height + chrome.spacing : 0)
          - (footer.visible ? footer.height + chrome.spacing : 0))
      }

      KeyHints {
        id: footer
        visible: root.hints.length > 0
        hints: root.hints
        opacity: bootIn.rowOpacity(bootIn.staggerCap)
      }
    }

    HudFrame { inset: bootIn.bracketInset; chamfer: shape.cut; chamferCorner: shape.cutCorner }
    Scanlines { shown: root.scanlines; flicker: true }
  }
}
