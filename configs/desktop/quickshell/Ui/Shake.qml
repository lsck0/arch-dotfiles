pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// a refused input's sideways shake: set as the item's transform, play() on the failure
Translate {
  id: root

  property real amplitude: Style.space(6)
  readonly property int stepMs: Style.motion.slow / 5

  function play() {
    if (Style.motion.enabled) shake.restart()
  }

  readonly property SequentialAnimation shake: SequentialAnimation {
    NumberAnimation { target: root; property: "x"; to: root.amplitude; duration: root.stepMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "x"; to: -root.amplitude; duration: root.stepMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "x"; to: root.amplitude / 2; duration: root.stepMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "x"; to: -root.amplitude / 2; duration: root.stepMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "x"; to: 0; duration: root.stepMs; easing.type: Easing.OutCubic }
  }
}
