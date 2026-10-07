import QtQuick
import Quickshell.Io
import qs.Commons

/**
 * Glitch: one-shot rgb split + row offset over a sibling item (signature B), then fully off.
 *
 * Only for lock, unlock and wallpaper change. While playing it hides the source and draws it through
 * shaders/glitch.frag.qsb for durationMs; idle it is invisible and holds no texture. When the baked
 * shader is missing (no qsb, see restart.sh), it failed to load, or motion is off, play() finishes
 * at once without touching the source.
 *
 * Properties:
 *   source  the item to glitch; must not be an ancestor of the Glitch
 *
 * Signals:
 *   finished()  after the run, or at once when skipped
 *
 * Usage:
 *   Item { id: content; anchors.fill: parent }
 *   Glitch { id: glitch; anchors.fill: content; source: content }
 *   glitch.play()
 */
Item {
  id: root

  property Item source: null
  property real u_progress: 0

  readonly property int durationMs: 180
  // rows the offset band is cut into
  readonly property int rows: 48
  readonly property string shaderPath: Paths.shellDir + "/shaders/glitch.frag.qsb"

  property bool baked: false
  readonly property bool playing: anim.running

  signal finished()

  function play() {
    if (!root.baked || !root.source || !Style.motion.enabled || effect.status === ShaderEffect.Error) {
      root.finished()
      return
    }
    effect.u_seed = Math.random() * 100
    anim.restart()
  }

  visible: playing

  // presence check only, synchronous so a lock surface created this instant can already play
  FileView {
    path: root.shaderPath
    blockLoading: true
    printErrors: false
    onLoaded: root.baked = true
    onLoadFailed: root.baked = false
  }

  ShaderEffectSource {
    id: capture
    sourceItem: root.playing ? root.source : null
    hideSource: root.playing && effect.status !== ShaderEffect.Error
    live: true
    visible: false
  }

  ShaderEffect {
    id: effect
    anchors.fill: parent
    property variant source: capture
    property real u_progress: root.u_progress
    property real u_rows: root.rows
    property real u_seed: 0
    fragmentShader: root.baked ? Util.fileUrl(root.shaderPath) : ""
  }

  NumberAnimation {
    id: anim
    target: root
    property: "u_progress"
    from: 0
    to: 1
    duration: root.durationMs
    onFinished: {
      root.u_progress = 0
      root.finished()
    }
  }
}
