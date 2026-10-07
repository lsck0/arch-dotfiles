import QtQuick
import qs.Commons

// the switch as text: `[on ]` / `[ off]`, fixed width so rows do not shift
Item {
  id: root

  property bool checked: false

  // off when the surrounding row owns the click
  property bool interactive: true

  property bool hasCursor: false

  property bool cursorRing: interactive
  property int cursorPad: Style.spacing.xs
  property color foreground: Color.foreground
  property color accent: Color.accent

  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  readonly property int _pad: cursorRing ? cursorPad : 0

  implicitWidth: widest.advanceWidth + _pad * 2
  implicitHeight: label.implicitHeight + _pad * 2

  TextMetrics {
    id: widest
    font: label.font
    text: "[ off]"
  }

  BorderSurface {
    anchors.fill: parent
    visible: root.cursorRing && root.hot
    color: "transparent"
    radius: Style.shape.data
    borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.checked ? "[on ]" : "[ off]"
    color: root.checked ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
    opacity: root.checked ? 1 : Style.emphasis.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: root.checked
    layer.enabled: Style.fx.glow > 0 && root.checked
    layer.effect: Glow {}
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
  }
}
