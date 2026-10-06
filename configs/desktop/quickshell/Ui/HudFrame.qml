import QtQuick
import qs.Commons

Item {
  id: root
  anchors.fill: parent
  anchors.margins: margin
  visible: shown && Style.fx.brackets
  z: 5

  // caller gate, combined with the fx setting
  property bool shown: true
  property color color: Color.accent
  property int len: Style.fx.bracketLen
  property int thick: Style.fx.bracketWidth
  property real strength: 0.9
  // negative pushes the brackets outward, off the content
  property real margin: 0

  // keep opposite arms from meeting on small surfaces
  readonly property int hlen: Math.max(0, Math.min(len, Math.floor(width / 2) - thick))
  readonly property int vlen: Math.max(0, Math.min(len, Math.floor(height / 2) - thick))

  component Arm: Rectangle {
    color: root.color
    opacity: root.strength
    antialiasing: false
  }

  Arm { x: 0; y: 0; width: root.hlen; height: root.thick }
  Arm { x: 0; y: 0; width: root.thick; height: root.vlen }
  Arm { anchors.right: parent.right; y: 0; width: root.hlen; height: root.thick }
  Arm { anchors.right: parent.right; y: 0; width: root.thick; height: root.vlen }
  Arm { x: 0; anchors.bottom: parent.bottom; width: root.hlen; height: root.thick }
  Arm { x: 0; anchors.bottom: parent.bottom; width: root.thick; height: root.vlen }
  Arm { anchors.right: parent.right; anchors.bottom: parent.bottom; width: root.hlen; height: root.thick }
  Arm { anchors.right: parent.right; anchors.bottom: parent.bottom; width: root.thick; height: root.vlen }
}
