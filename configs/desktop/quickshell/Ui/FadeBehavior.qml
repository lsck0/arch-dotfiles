import QtQuick
import qs.Commons

// The shell's fade: base and the enter curve on the way in, exit and the leave curve on the way out. entering defaults
// to a rise above 0 (opacity); a slide sets its own (`entering: targetValue === 0`).
Behavior {
  id: root

  property bool entering: targetValue > 0

  NumberAnimation {
    duration: Style.motion.fadeMs(root.entering)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Style.motion.curve(root.entering)
  }
}
