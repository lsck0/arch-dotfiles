import QtQuick
import qs.Commons

// A column of toasts (alerts, notification popups): a toast enters from the shell's one travel distance and leaves all
// the way to the list's edge, the rest shifting at base; the list's own opacity fades like FadeBehavior.
ListView {
  id: root

  FadeBehavior on opacity {}

  add: Transition {
    NumberAnimation { property: "x"; from: Style.motion.travel; to: 0; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
  }
  remove: Transition {
    NumberAnimation { property: "x"; to: root.width; duration: Style.motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.leave }
    NumberAnimation { property: "opacity"; to: 0; duration: Style.motion.exit; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.leave }
  }
  displaced: Transition {
    NumberAnimation { properties: "x,y"; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
    NumberAnimation { property: "opacity"; to: 1; duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
  }
}
