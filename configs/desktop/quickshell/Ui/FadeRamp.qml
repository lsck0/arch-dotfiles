import QtQuick
import qs.Commons

// the alpha mask a FadeMask reads: opaque inside, fading over reach at each edge by that edge's strength (0 to 1)
Item {
  id: root

  property real reach: 0
  property real fadeTop: 0
  property real fadeBottom: 0
  // below 1 the mask is a wipe from the top instead, its edge as soft as a fade, fully open at 1
  property real reveal: 1
  readonly property real ramp: reach / Math.max(1, height)
  readonly property real revealEdge: reveal * (1 + ramp)

  visible: false

  Rectangle {
    anchors.fill: parent
    visible: root.reveal < 1
    gradient: Gradient {
      GradientStop { position: Math.max(0, Math.min(1, root.revealEdge - root.ramp)); color: "black" }
      GradientStop {
        position: Math.min(1, root.revealEdge)
        color: Util.alpha("black", Math.max(0, Math.min(1, (root.revealEdge - 1) / Math.max(0.0001, root.ramp))))
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: root.reveal >= 1
    gradient: Gradient {
      GradientStop { position: 0; color: Util.alpha("black", 1 - root.fadeTop) }
      GradientStop { position: Math.min(0.5, root.ramp); color: "black" }
      GradientStop { position: Math.max(0.5, 1 - root.ramp); color: "black" }
      GradientStop { position: 1; color: Util.alpha("black", 1 - root.fadeBottom) }
    }
  }
}
