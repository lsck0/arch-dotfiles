import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.Commons
import qs.Ui

// session lock is fail-secure; no unlock ipc on purpose (auth bypass)
Item {
  id: root

  property bool locked: false
  property bool authError: false
  property string primaryScreenName: ""
  // in-flight pam response; the field enter was pressed in is the source of truth
  property string _pw: ""
  property var activeField: null
  signal clearFields()

  function lock() {
    if (root.locked) return
    root.authError = false
    root._pw = ""
    var scr = Quickshell.screens
    root.primaryScreenName = (scr && scr.length) ? String(scr[0].name) : ""
    root.locked = true
  }

  // only a successful pam result may call this
  function unlock() {
    root.locked = false
    root.authError = false
    root._pw = ""
    root.clearFields()
    pamPw.active = false
  }

  function submit() {
    if (!root.locked || !root.activeField || root.activeField.text.length === 0) return
    root._pw = root.activeField.text
    root.authError = false
    pamPw.start()
  }

  function fail() {
    root.authError = true
    root._pw = ""
    root.clearFields()
  }

  IpcHandler {
    target: "lock"
    function lock(): string { root.lock(); return "ok" }
    function isLocked(): string { return root.locked ? "true" : "false" }
  }

  PamContext {
    id: pamPw
    config: "quickshell-lock"
    onResponseRequiredChanged: if (responseRequired) respond(root._pw)
    onCompleted: function(result) {
      if (result === PamResult.Success) root.unlock()
      else root.fail()
      active = false
    }
    onError: function(err) { root.fail(); active = false }
  }

  property string statsText: ""
  Process {
    id: statsProc
    command: ["bash", "-c", "timeout 4s \"${XDG_CONFIG_HOME:-$HOME/.config}\"/hypr/lockscreen-stats.sh"]
    stdout: StdioCollector { onStreamFinished: root.statsText = String(text).trim() }
  }
  Timer {
    interval: 5000
    running: root.locked
    repeat: true
    triggeredOnStart: true
    onTriggered: statsProc.running = true
  }

  property string clockText: "00//00//00"
  property string dateText: ""
  Timer {
    interval: 1000
    running: root.locked
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var now = new Date()
      root.clockText = Qt.formatDateTime(now, "HH//mm//ss")
      root.dateText = Qt.formatDateTime(now, ">> dd/MM/yy")
    }
  }

  WlSessionLock {
    locked: root.locked

    // rain and the auth hud on every screen: hyprland gives the keyboard to the surface under the cursor
    WlSessionLockSurface {
      id: surface
      color: Color.background

      readonly property bool isPrimary:
        root.primaryScreenName === "" || (screen && String(screen.name) === root.primaryScreenName)

      // faint blurred wallpaper; unset while unlocked so each lock decodes the current one
      Image {
        anchors.fill: parent
        source: root.locked ? Util.fileUrl(Quickshell.env("HOME") + "/.cache/wal/wallpaper") : ""
        cache: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(surface.width, surface.height)
        opacity: 0.35
        layer.enabled: true
        layer.effect: MultiEffect {
          blurEnabled: true
          blur: 1.0
          blurMax: 64
        }
      }

      RainField { anchors.fill: parent; running: surface.visible && Style.fx.matrixRain > 0 }

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.lg

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.clockText
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.display * 1.8)
          font.bold: true
          font.letterSpacing: Style.displayTracking
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: root.dateText
          color: Color.foreground
          opacity: Style.emphasis.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.letterSpacing: Style.headerTracking
        }

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(320)
          height: Style.space(46)
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.55)
          border.width: root.authError ? 2 : 1
          border.color: root.authError ? Color.urgent
            : (pwField.activeFocus ? Color.accent : Style.normalBorderColor)
          radius: Style.cornerRadius
          // hidden until typing starts; keeps focus, so the first key still lands in the field
          opacity: (pwField.text.length > 0 || root.authError || pamPw.active) ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 140 } }

          TextField {
            id: pwField
            anchors.fill: parent
            anchors.margins: Style.spacing.xs
            echoMode: TextInput.Password
            enabled: root.locked
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.letterSpacing: Style.headerTracking * 0.5
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            placeholderText: root.authError ? "  ACCESS DENIED" : "> AUTH REQUIRED"
            placeholderTextColor: root.authError ? Color.urgent : Qt.darker(Color.foreground, 1.6)
            background: null
            onTextEdited: root.authError = false
            onAccepted: { root.activeField = pwField; root.submit() }
            Keys.onEscapePressed: text = ""
            Connections {
              target: root
              function onClearFields() { pwField.text = "" }
            }
          }
        }
      }

      Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Style.spacing.huge
        visible: surface.isPrimary
        textFormat: Text.PlainText
        text: root.statsText
        color: Color.foreground
        opacity: Style.emphasis.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      HudFrame {}
      Scanlines { flicker: false }

      onVisibleChanged: if (visible) Qt.callLater(function() { pwField.forceActiveFocus() })
      Component.onCompleted: Qt.callLater(function() { pwField.forceActiveFocus() })
    }
  }
}
