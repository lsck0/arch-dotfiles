import QtQuick
import qs.Commons

/**
 * BlinkCaret: the terminal "_" after hud titles and prompt lines, one blink for the whole shell.
 *
 * Properties:
 *   running  blinks while true, sits solid while false (bind to the owner's open state)
 *   size     font pixel size
 *   color    inherited from Text, accent by default
 *
 * Usage:
 *   BlinkCaret { size: Style.font.title; running: root.opened }
 */
Text {
  id: root

  property bool running: true
  property int size: Style.font.caption

  // half period of a terminal cursor, the hard step reads as a cursor where a fade reads as a pulse
  readonly property int blinkMs: 530

  textFormat: Text.PlainText
  text: "_"
  color: Color.accent
  font.family: Style.font.family
  font.pixelSize: size
  layer.enabled: Style.fx.glow > 0
  layer.effect: Glow {}

  // a stop can land on the dark phase
  onRunningChanged: if (!running) opacity = 1

  SequentialAnimation on opacity {
    running: root.running
    loops: Animation.Infinite
    PropertyAnimation { to: 1; duration: 0 }
    PauseAnimation { duration: root.blinkMs }
    PropertyAnimation { to: 0; duration: 0 }
    PauseAnimation { duration: root.blinkMs }
  }
}
