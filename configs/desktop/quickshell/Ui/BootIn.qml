import QtQuick
import qs.Commons

/**
 * BootIn: the cold boot of a surface (signature B). Draws nothing, drives its host.
 *
 * On active: progress eases 0 -> 1 over motion.base (brackets fly from the centre to the corners,
 * drawers grow), the title types one char per typeStepMs on a self-stopping timer, rows fade in
 * staggerMs apart (capped at staggerCap) inside motion.boot. Inactive replays it backwards at
 * motion.closeRate of the time. Power saver jumps to the end state. Nothing loops.
 *
 * Properties:
 *   active        target state, bind to the host's open flag
 *   title         text to type; typedTitle / typed follow it
 *   span          half the host's smaller side, where the brackets start
 *   progress      eased 0..1, 0 means fully closed (unmap the window then)
 *   bracketInset  HudFrame.inset while booting
 *   rowOpacity(i) staggered fade for row i
 *
 * Usage:
 *   BootIn { id: boot; active: root.open; title: root.title; span: Math.min(card.width, card.height) / 2 }
 *   HudFrame { inset: boot.bracketInset }
 */
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property bool active: false
  property string title: ""
  property real span: 0

  property real progress: 0
  // linear 0..1 over motion.boot, the row stagger timeline
  property real phase: 0
  property int typed: 0

  readonly property int typeStepMs: 12
  readonly property int staggerMs: 15
  readonly property int staggerCap: 8
  // nominal boot length, the stagger is laid out on it even when power saver zeroes the token
  readonly property int timelineMs: 220

  readonly property string typedTitle: title.substring(0, typed)
  readonly property real bracketInset: (1 - progress) * span
  readonly property bool running: anim.running

  function rowOpacity(index) {
    var start = Math.min(Math.max(0, index), staggerCap) * staggerMs / timelineMs
    var len = 1 - staggerCap * staggerMs / timelineMs
    return Math.max(0, Math.min(1, (phase - start) / len))
  }

  function run() {
    anim.stop()
    var opening = root.active
    var rate = opening ? 1 : Style.motion.closeRate
    progressAnim.to = opening ? 1 : 0
    progressAnim.duration = Math.round(Style.motion.base * rate)
    progressAnim.easing.bezierCurve = opening ? Style.motion.enter : Style.motion.leave
    phaseAnim.to = opening ? 1 : 0
    phaseAnim.duration = Math.round(Style.motion.boot * rate)
    if (opening) {
      root.typed = Style.motion.enabled ? 0 : root.title.length
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
