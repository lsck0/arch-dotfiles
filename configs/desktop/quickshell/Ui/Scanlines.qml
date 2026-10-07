import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root
  anchors.fill: parent
  visible: shown && (Style.fx.scanlineOpacity > 0 || Style.fx.flicker > 0)
  z: 10

  // caller gate, combined with the fx settings
  property bool shown: true
  property int spacing: Style.fx.scanlineSpacing
  property real strength: Style.fx.scanlineOpacity
  // opt-in: two flicker cycles when the surface appears, never a loop
  property bool flicker: false
  readonly property int flickerCycles: 2

  // items keep visible: true inside a hidden window, endless animations would tick unseen
  readonly property bool onScreen: visible && (QsWindow.window ? QsWindow.window.visible : true)

  // a canvas holds a window-sized image, so it only exists while the window shows
  Loader {
    anchors.fill: parent
    active: root.onScreen && root.strength > 0
    sourceComponent: Canvas {
      id: cv
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
  }

  Rectangle {
    anchors.fill: parent
    color: Color.accent
    opacity: 0
    visible: root.flicker && Style.fx.flicker > 0
    SequentialAnimation on opacity {
      running: root.flicker && Style.fx.flicker > 0 && root.onScreen && Style.motion.enabled
      loops: root.flickerCycles
      NumberAnimation { to: Style.fx.flicker; duration: Style.motion.fast }
      NumberAnimation { to: 0; duration: Style.motion.base }
    }
  }
}
