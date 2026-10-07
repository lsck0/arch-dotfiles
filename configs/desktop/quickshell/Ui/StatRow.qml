import QtQuick
import qs.Commons

/**
 * StatRow: one `LABEL ........ value note` line, value right-aligned in fixed-width digits.
 *
 * Properties:
 *   label       left, caption uppercase
 *   value       right; "--" while unknown
 *   note        faint text after the value, "" hides it (stale ages read " ~12m")
 *   valueColor  value tint, e.g. Color.urgent for an alert
 *   dim         value at faint emphasis
 *   valueElide  how a too-long value shortens (it may take valueShare of the row)
 *   clickable   hover fill and pointer, emits activated()
 *
 * Usage:
 *   StatRow { label: "uptime"; value: root.uptime; note: root.stale }
 */
Item {
  id: root

  property string label: ""
  property string value: "--"
  property string note: ""
  property color valueColor: Color.menu.text
  property bool dim: false
  property int valueElide: Text.ElideRight
  readonly property real valueShare: 0.65
  property bool clickable: false

  signal activated()

  width: parent ? parent.width : implicitWidth
  implicitWidth: labelText.implicitWidth + valueRow.implicitWidth + Style.spacing.md
  implicitHeight: valueText.implicitHeight + Style.spacing.xxs * 2

  // bleeds past the edge so the text stays aligned with headers
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
    color: Color.menu.text
    elide: Text.ElideRight
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Style.headerTracking * 0.4
  }

  Row {
    id: valueRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Text {
      id: valueText
      width: Math.min(implicitWidth, root.width * root.valueShare)
      elide: root.valueElide
      textFormat: Text.PlainText
      text: root.value
      color: root.valueColor
      opacity: root.dim ? Style.emphasis.faint : 1
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }
    Text {
      visible: root.note !== ""
      textFormat: Text.PlainText
      text: root.note
      color: Color.menu.text
      opacity: Style.emphasis.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
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
