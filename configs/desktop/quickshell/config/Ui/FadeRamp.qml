import QtQuick
import qs.Commons

// the alpha mask a FadeMask reads: opaque inside, fading over reach at each edge by that edge's strength (0 to 1)
Item {
  id: root

  property real reach: 0
  property real fadeTop: 0
  property real fadeBottom: 0
  readonly property real ramp: reach / Math.max(1, height)

  visible: false

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Util.alpha("black", 1 - root.fadeTop) }
      GradientStop { position: Math.min(0.5, root.ramp); color: "black" }
      GradientStop { position: Math.max(0.5, 1 - root.ramp); color: "black" }
      GradientStop { position: 1; color: Util.alpha("black", 1 - root.fadeBottom) }
    }
  }
}
