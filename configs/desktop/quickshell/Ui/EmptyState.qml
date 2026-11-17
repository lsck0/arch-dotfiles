import QtQuick
import qs.Commons

// What a list says while it has no rows: a glyph over one dim line, centred in its parent and faded in and out.
Column {
  id: root

  property bool shown: false
  property string glyph: ""
  property real glyphSize: Style.font.display
  property string text: ""

  anchors.centerIn: parent
  spacing: Style.spacing.sm
  opacity: shown ? 1 : 0
  visible: opacity > 0
  Behavior on opacity {
    id: fade
    NumberAnimation {
      duration: Style.motion.fadeMs(fade.targetValue > 0)
      easing.type: Easing.BezierSpline
      easing.bezierCurve: Style.motion.curve(fade.targetValue > 0)
    }
  }
  width: parent.width * 0.8

  Label {
    text: root.glyph
    color: Colors.accentText
    opacity: Style.emphasis.dim
    icon: true
    font.pixelSize: root.glyphSize
    horizontalAlignment: Text.AlignHCenter
    width: parent.width
  }

  Label {
    text: root.text
    dim: true
    horizontalAlignment: Text.AlignHCenter
    width: parent.width
  }
}
