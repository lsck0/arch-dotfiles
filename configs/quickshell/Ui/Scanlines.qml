import QtQuick
import qs.Commons

// Non-interactive CRT scanline + subtle flicker overlay for any surface.
Item {
  id: root
  anchors.fill: parent
  visible: Style.fx.scanlineOpacity > 0 || Style.fx.flicker > 0
  z: 10

  property int spacing: Style.fx.scanlineSpacing
  property real strength: Style.fx.scanlineOpacity

  Canvas {
    id: cv
    anchors.fill: parent
    visible: root.strength > 0
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.strokeStyle = Qt.rgba(0, 0, 0, root.strength)
      ctx.lineWidth = 1
      for (var y = 0.5; y < height; y += root.spacing) {
        ctx.beginPath()
        ctx.moveTo(0, y)
        ctx.lineTo(width, y)
        ctx.stroke()
      }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections {
      target: Theme
      function onRevisionChanged() { cv.requestPaint() }
    }
  }

  // CRT brightness flicker
  Rectangle {
    anchors.fill: parent
    color: Color.accent
    opacity: 0
    visible: Style.fx.flicker > 0
    SequentialAnimation on opacity {
      running: Style.fx.flicker > 0
      loops: Animation.Infinite
      NumberAnimation { to: Style.fx.flicker; duration: 90 }
      NumberAnimation { to: 0; duration: 130 }
      PauseAnimation { duration: 380 }
    }
  }
}
