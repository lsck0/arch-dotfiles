import QtQuick
import qs.Commons

/**
 * BlinkCaret: the terminal "_" after hud titles and prompt lines, one blink for the whole shell.
 *
 * The only endless animation the shell allows, and only on a focused prompt: a title caret blinks for
 * titleBlinkMs after running turns true, then sits solid. Power saver keeps it solid.
 *
 * Properties:
 *   running  blinks while true, sits solid while false (bind to the owner's open state)
 *   prompt   true for a focused text prompt, which blinks for as long as running
 *   size     font pixel size
 *   block    a filled cell instead of "_" (the lock's password prompt)
 *   color    inherited from Text, accent by default
 *
 * Usage:
 *   BlinkCaret { size: Style.font.title; running: root.opened }
 *   BlinkCaret { prompt: true; running: root.opened && input.activeFocus }
 */
Text {
  id: root

  property bool running: true
  property bool prompt: false
  property int size: Style.font.caption
  property bool block: false

  // half period of a terminal cursor, the hard step reads as a cursor where a fade reads as a pulse
  readonly property int blinkMs: 530
  // a title caret only marks the surface as fresh
  readonly property int titleBlinkMs: 10000

  property bool expired: false
  readonly property bool blinking: running && !expired && !Power.saver

  textFormat: Text.PlainText
  // a space keeps the cell one advance wide for the block
  text: block ? " " : "_"
  color: Color.accent
  font.family: Style.font.family
  font.pixelSize: size
  layer.enabled: Style.fx.glow > 0
  layer.effect: Glow {}

  onRunningChanged: {
    expired = false
    if (running && !prompt) expiry.restart()
    else expiry.stop()
  }
  Component.onCompleted: if (running && !prompt) expiry.start()

  Timer {
    id: expiry
    interval: root.titleBlinkMs
    onTriggered: root.expired = true
  }

  // a stop can land on the dark phase
  onBlinkingChanged: if (!blinking) opacity = 1

  Rectangle {
    visible: root.block
    anchors.fill: parent
    color: root.color
  }

  SequentialAnimation on opacity {
    running: root.blinking
    loops: Animation.Infinite
    PropertyAnimation { to: 1; duration: 0 }
    PauseAnimation { duration: root.blinkMs }
    PropertyAnimation { to: 0; duration: 0 }
    PauseAnimation { duration: root.blinkMs }
  }
}
