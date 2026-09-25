import QtQuick
import qs.Commons

// HUD corner brackets framing the parent surface (sci-fi terminal look).
Item {
  id: root
  anchors.fill: parent
  anchors.margins: margin
  visible: Style.fx.brackets
  z: 5

  property color color: Color.accent
  property int len: Style.fx.bracketLen
  property int thick: Style.fx.bracketWidth
  property real strength: 0.9
  // negative pushes the brackets outward, off the content
  property real margin: 0

  component Arm: Rectangle {
    color: root.color
    opacity: root.strength
    antialiasing: false
  }

  // top-left
  Arm { x: 0; y: 0; width: root.len; height: root.thick }
  Arm { x: 0; y: 0; width: root.thick; height: root.len }
  // top-right
  Arm { anchors.right: parent.right; y: 0; width: root.len; height: root.thick }
  Arm { anchors.right: parent.right; y: 0; width: root.thick; height: root.len }
  // bottom-left
  Arm { x: 0; anchors.bottom: parent.bottom; width: root.len; height: root.thick }
  Arm { x: 0; anchors.bottom: parent.bottom; width: root.thick; height: root.len }
  // bottom-right
  Arm { anchors.right: parent.right; anchors.bottom: parent.bottom; width: root.len; height: root.thick }
  Arm { anchors.right: parent.right; anchors.bottom: parent.bottom; width: root.thick; height: root.len }
}
