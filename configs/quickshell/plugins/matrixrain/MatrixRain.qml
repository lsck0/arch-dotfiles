import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// IPC-triggerable digital-rain screensaver: ASCII phosphor rain behind a glowing
// terminal clock and STANDBY readout. Any key or pointer motion dismisses it.
Item {
  id: root

  property bool opened: false
  // Grace after opening: ignore the keypress/pointer event that launched it.
  property bool armed: false
  Timer { id: armTimer; interval: 450; onTriggered: root.armed = true }

  function open() {
    root.opened = true
    root.armed = false
    armTimer.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() { if (root.armed) root.opened = false }
  function toggle() { if (root.opened) root.close(); else root.open() }

  IpcHandler {
    target: "matrixrain"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "quickshell-matrixrain"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      // Big glowing terminal clock, refreshed once a second while visible.
      property string clockText: "00:00:00"

      // Opaque backdrop so the desktop underneath is fully hidden.
      Rectangle { anchors.fill: parent; color: Color.background }

      // The digital-rain field.
      Canvas {
        id: rain
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        // Per-column head row and fall speed; rebuilt when the grid size changes.
        property var drops: []
        property int cell: Math.max(Style.space(12), Style.font.body)
        property int cols: Math.max(1, Math.floor(width / cell))
        property int rows: Math.max(1, Math.floor(height / cell))
        // ASCII-only glyph pool (decorative-symbol rule).
        readonly property string charset: "01<>[]{}/\\|=+-*!?$#@abcdef0123456789"
        readonly property int trail: 16

        function reseed() {
          var d = []
          for (var c = 0; c < cols; c++)
            d.push({ y: -Math.floor(Math.random() * rows), speed: 0.4 + Math.random() * 0.9 })
          drops = d
        }

        function glyph() { return charset.charAt(Math.floor(Math.random() * charset.length)) }

        onColsChanged: reseed()
        Component.onCompleted: reseed()

        onPaint: {
          var ctx = getContext("2d")
          // Fade the previous frame toward the background instead of clearing:
          // leaves fading trails, draws only the new heads, and never flashes.
          var bg = Color.background
          ctx.fillStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.14)
          ctx.fillRect(0, 0, width, height)
          var lead = Qt.lighter(Color.accent, 1.7)
          ctx.fillStyle = Qt.rgba(lead.r, lead.g, lead.b, 1)
          ctx.font = cell + "px " + Style.font.family
          ctx.textBaseline = "top"
          // Density gates how many columns actually rain.
          var density = Style.fx.matrixRain
          for (var i = 0; i < drops.length; i++) {
            if ((i % 7) / 7 > density + 0.02) continue
            var ry = Math.floor(drops[i].y)
            if (ry < 0 || ry > rows) continue
            ctx.fillText(glyph(), i * cell, ry * cell)
          }
        }
      }

      // Advances every column head and repaints; a spent column respawns at the top.
      Timer {
        interval: 90
        running: panel.visible
        repeat: true
        onTriggered: {
          var d = rain.drops
          for (var i = 0; i < d.length; i++) {
            d[i].y += d[i].speed
            if (d[i].y - rain.trail > rain.rows && Math.random() > 0.975) {
              d[i].y = -Math.floor(Math.random() * 8)
              d[i].speed = 0.4 + Math.random() * 0.9
            }
          }
          rain.requestPaint()
        }
      }

      Timer {
        interval: 1000
        running: panel.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: panel.clockText = Qt.formatDateTime(new Date(), "HH:mm:ss")
      }

      // Any pointer motion or click wakes the session.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: root.close()
        onClicked: root.close()
      }

      // Any key wakes the session.
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { root.close(); event.accepted = true }
      }

      // Centred HUD readout stack over the rain.
      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.lg

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: panel.clockText
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.display * 2)
          font.bold: true
          font.letterSpacing: Style.displayTracking
          layer.enabled: Style.fx.glow > 0
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Style.fx.glowColor
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
            blurMax: Style.fx.glowRadius
            autoPaddingEnabled: true
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: ":: STANDBY // SESSION IDLE"
          color: Color.accent
          opacity: Style.emphasis.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: Style.headerTracking
        }
      }

      // Wake hint pinned to the bottom, blinking caret terminal-style.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.huge
        spacing: Style.spacing.sm

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "> PRESS ANY KEY TO RESUME"
          color: Color.foreground
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: Style.headerTracking * 0.5
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "_"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          SequentialAnimation on opacity {
            running: panel.visible
            loops: Animation.Infinite
            PropertyAnimation { to: 1; duration: 0 }
            PauseAnimation { duration: 530 }
            PropertyAnimation { to: 0; duration: 0 }
            PauseAnimation { duration: 530 }
          }
        }
      }

      // Screen-corner HUD brackets + CRT scanlines on top of the rain.
      HudFrame {}
      Scanlines {}
    }
  }
}
