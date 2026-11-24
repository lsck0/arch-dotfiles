import QtQuick
import qs.Commons

Item {
  id: root

  property string label: ""
  property string value: "--"
  property string note: ""
  property color valueColor: Colors.menu.text
  property bool dim: false
  property int valueElide: Text.ElideRight
  readonly property real valueShare: 0.65
  // a clickable row is a link: focusable, activated by Enter or Space, and as tall as any other control
  property bool clickable: false
  readonly property bool highlighted: clickable && (activeFocus || mouse.containsMouse)

  signal activated()

  width: parent ? parent.width : implicitWidth
  implicitWidth: labelText.implicitWidth + valueRow.implicitWidth + Style.spacing.md
  implicitHeight: Math.max(clickable ? Style.row.control : 0, valueText.implicitHeight + Style.spacing.xxs * 2)
  activeFocusOnTab: clickable
  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.spacing.xs
    anchors.rightMargin: -Style.spacing.xs
    radius: Style.shape.data
    color: !root.clickable ? "transparent"
      : root.activeFocus ? Style.focusFill
      : mouse.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Label {
    id: labelText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, parent.width - valueRow.width - Style.spacing.md)
    text: root.label
    color: Colors.menu.text
    elide: Text.ElideRight
    caption: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Style.labelTracking
  }

  Label {
    clip: true
    anchors.left: labelText.right
    anchors.leftMargin: Style.spacing.xs
    anchors.right: valueRow.left
    anchors.rightMargin: Style.spacing.xs
    anchors.baseline: labelText.baseline
    horizontalAlignment: Text.AlignRight
    text: "\u00b7 ".repeat(120)
    color: Util.alpha(Colors.menu.text, Style.emphasis.disabled)
    caption: true
  }

  Row {
    id: valueRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    Label {
      id: valueText
      width: Math.min(implicitWidth, root.width * root.valueShare)
      elide: root.valueElide
      text: root.value
      color: root.dim && !root.highlighted ? Colors.textDim : root.valueColor
      caption: true
      font.features: { "tnum": 1 }
    }
    Label {
      visible: root.note !== ""
      text: root.note
      dim: true
      highlighted: root.highlighted
      caption: true
      font.features: { "tnum": 1 }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.clickable
    hoverEnabled: root.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
