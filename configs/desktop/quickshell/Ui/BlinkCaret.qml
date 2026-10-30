import QtQuick
import qs.Commons

Text {
  id: root

  property bool running: true
  property bool prompt: false
  property int size: Style.font.caption
  property bool block: false

  readonly property int blinkMs: 530
  readonly property int titleBlinkMs: 10000

  property bool expired: false
  readonly property bool blinking: running && !expired && !Power.saver

  textFormat: Text.PlainText
  text: block ? " " : "_"
  color: Colors.accentText
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
