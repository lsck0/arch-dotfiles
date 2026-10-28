import QtQuick
import qs.Commons

Item {
  id: root

  visible: false
  width: 0
  height: 0

  property bool active: false
  property string title: ""
  property real span: 0
  property bool instant: false

  property real progress: 0
  property real phase: 0
  property int typed: 0

  readonly property int typeStepMs: 12
  readonly property int staggerMs: 15
  readonly property int staggerCap: 8
  readonly property int timelineMs: 220

  readonly property real bracketInset: (1 - progress) * span

  function rowOpacity(index) {
    var start = Math.min(Math.max(0, index), staggerCap) * staggerMs / timelineMs
    var len = 1 - staggerCap * staggerMs / timelineMs
    return Math.max(0, Math.min(1, (phase - start) / len))
  }

  function run() {
    anim.stop()
    var opening = root.active
    var rate = (opening ? 1 : Style.motion.closeRate) * (root.instant ? Style.motion.switchRate : 1)
    progressAnim.to = opening ? 1 : 0
    progressAnim.duration = Math.round(Style.motion.base * rate)
    progressAnim.easing.bezierCurve = opening ? Style.motion.enter : Style.motion.leave
    phaseAnim.to = opening ? 1 : 0
    phaseAnim.duration = Math.round(Style.motion.boot * rate)
    if (opening) {
      root.typed = (Style.motion.enabled && !root.instant) ? 0 : root.title.length
      if (root.typed < root.title.length) typer.restart()
    } else {
      typer.stop()
    }
    anim.start()
  }

  onActiveChanged: run()
  onTitleChanged: if (!typer.running) typed = title.length
  Component.onCompleted: if (active) run()

  ParallelAnimation {
    id: anim
    NumberAnimation { id: progressAnim; target: root; property: "progress"; easing.type: Easing.BezierSpline }
    NumberAnimation { id: phaseAnim; target: root; property: "phase" }
  }

  Timer {
    id: typer
    interval: root.typeStepMs
    repeat: true
    onTriggered: {
      root.typed++
      if (root.typed >= root.title.length) stop()
    }
  }
}
