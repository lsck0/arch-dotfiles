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
  property bool clickable: false

  signal activated()

  width: parent ? parent.width : implicitWidth
  implicitWidth: labelText.implicitWidth + valueRow.implicitWidth + Style.spacing.md
  implicitHeight: valueText.implicitHeight + Style.spacing.xxs * 2

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.spacing.xs
    anchors.rightMargin: -Style.spacing.xs
    radius: Style.shape.data
    color: mouse.containsMouse && root.clickable ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, parent.width - valueRow.width - Style.spacing.md)
    textFormat: Text.PlainText
    text: root.label
    color: Colors.menu.text
    elide: Text.ElideRight
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Style.labelTracking
  }

  Text {
    clip: true
    anchors.left: labelText.right
    anchors.leftMargin: Style.spacing.xs
    anchors.right: valueRow.left
    anchors.rightMargin: Style.spacing.xs
    anchors.baseline: labelText.baseline
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    text: "\u00b7 ".repeat(120)
    color: Util.alpha(Colors.menu.text, Style.emphasis.disabled)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Row {
    id: valueRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    Text {
      id: valueText
      width: Math.min(implicitWidth, root.width * root.valueShare)
      elide: root.valueElide
      textFormat: Text.PlainText
      text: root.value
      color: root.dim ? Colors.textDim : root.valueColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }
    Text {
      visible: root.note !== ""
      textFormat: Text.PlainText
      text: root.note
      color: Colors.textDim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
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
