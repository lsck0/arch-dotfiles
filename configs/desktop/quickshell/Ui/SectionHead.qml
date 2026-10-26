import QtQuick
import qs.Commons

// A panel section header across the panel width: a rule after the title, or extras (tags) right-aligned in its place.
Item {
  id: head

  property string text: ""
  default property alias extras: extrasRow.data

  width: parent ? parent.width : 0
  implicitHeight: Math.max(title.implicitHeight, extrasRow.implicitHeight)
  height: implicitHeight

  PanelSectionHeader {
    id: title
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: head.text
  }

  Rectangle {
    visible: extrasRow.children.length === 0
    anchors.left: title.right
    anchors.leftMargin: Style.spacing.xs
    anchors.right: parent.right
    anchors.verticalCenter: title.verticalCenter
    height: 1
    color: Util.alpha(Colors.accent, 0.35)
  }

  Row {
    id: extrasRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs
  }
}
