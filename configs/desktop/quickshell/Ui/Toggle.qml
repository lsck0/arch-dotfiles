import QtQuick
import qs.Commons

Item {
  id: root

  property bool checked: false

  property bool interactive: true

  property bool hasCursor: false

  property color foreground: Colors.foreground
  property color accent: Colors.accent

  readonly property bool hot: hasCursor || mouse.containsMouse || activeFocus

  signal toggled(bool checked)

  activeFocusOnTab: interactive
  Keys.onSpacePressed: root.toggled(!root.checked)
  Keys.onReturnPressed: root.toggled(!root.checked)
  Keys.onEnterPressed: root.toggled(!root.checked)

  readonly property int _pad: interactive ? Style.spacing.xs : 0

  implicitWidth: widest.advanceWidth + _pad * 2
  implicitHeight: label.implicitHeight + _pad * 2

  TextMetrics {
    id: widest
    font: label.font
    text: "[off]"
  }

  BorderSurface {
    anchors.fill: parent
    visible: root.interactive && root.hot
    color: "transparent"
    radius: Style.shape.data
    borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  Label {
    id: label
    anchors.right: parent.right
    anchors.rightMargin: root._pad
    anchors.verticalCenter: parent.verticalCenter
    // flush right like the [state] of a multi-state toggle, so both read as one column
    text: root.checked ? "[on]" : "[off]"
    color: root.checked ? Colors.textFor(root.accent) : Colors.textDim
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
    onClicked: root.toggled(!root.checked)
  }
}
