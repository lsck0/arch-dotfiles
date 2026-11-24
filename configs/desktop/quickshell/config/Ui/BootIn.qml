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
  readonly property int staggerCap: 8
  // each row starts this share of the boot timeline after the one above it; rows from staggerCap on start together
  readonly property real staggerStep: 1 / 16

  readonly property real bracketInset: (1 - progress) * span

  // phase is the linear timeline; each row eases out of it like the card does (cubic out in, cubic in on the way out)
  function rowOpacity(index) {
    var start = Math.min(Math.max(0, index), staggerCap) * staggerStep
    var t = Math.max(0, Math.min(1, (phase - start) / (1 - staggerCap * staggerStep)))
    return 1 - Math.pow(1 - t, 3)
  }

  function run() {
    anim.stop()
    var opening = root.active
    var rate = root.instant ? Style.motion.switchRate : 1
    progressAnim.to = opening ? 1 : 0
    progressAnim.duration = Math.round(Style.motion.fadeMs(opening) * rate)
    progressAnim.easing.bezierCurve = Style.motion.curve(opening)
    phaseAnim.to = opening ? 1 : 0
    phaseAnim.duration = Math.round((opening ? Style.motion.boot : Style.motion.exit) * rate)
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
