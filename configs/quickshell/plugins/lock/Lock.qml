import QtQuick
import QtQuick.Controls
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
  property bool fpAvailable: false
  property string primaryScreenName: ""
  // in-flight pam response; the field enter was pressed in is the source of truth
  property string _pw: ""
  property var activeField: null
  signal clearFields()

  function lock() {
    if (root.locked) return
    root.authError = false
    root._pw = ""
    root.fpAvailable = false
    var scr = Quickshell.screens
    root.primaryScreenName = (scr && scr.length) ? String(scr[0].name) : ""
    root.locked = true
    fpDetect.running = true
  }

  // only a successful pam result may call this
  function unlock() {
    root.locked = false
    root.authError = false
    root._pw = ""
    root.clearFields()
    pamPw.active = false
    pamFp.active = false
    fpRetry.stop()
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

  Process {
    id: fpDetect
    command: ["bash", "-c",
      'command -v fprintd-list >/dev/null 2>&1 || { echo no; exit 0; }; '
      + 'out=$(timeout 5s fprintd-list "$USER" 2>/dev/null || true); '
      + 'if grep -qE "^found [1-9][0-9]* devices?$" <<<"$out" '
      + '&& grep -qE "^ - #[0-9]+: .+" <<<"$out"; then echo yes; else echo no; fi']
    stdout: StdioCollector {
      onStreamFinished: {
        root.fpAvailable = (String(text).trim() === "yes")
        if (root.fpAvailable && root.locked) pamFp.start()
      }
    }
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

  // separate context so a swipe and a password race independently
  PamContext {
    id: pamFp
    config: "quickshell-lock-fprint"
    onCompleted: function(result) {
      if (result === PamResult.Success) root.unlock()
      else if (root.locked && root.fpAvailable) fpRetry.restart()
      active = false
    }
    onError: function(err) { if (root.locked && root.fpAvailable) fpRetry.restart(); active = false }
  }
  // pam_fprintd completes per swipe; keep listening
  Timer {
    id: fpRetry
    interval: 800
    onTriggered: if (root.locked && root.fpAvailable) pamFp.start()
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

      RainField { anchors.fill: parent; running: surface.visible }

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

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.fpAvailable
          textFormat: Text.PlainText
          text: (pamFp.message && pamFp.message.length) ? (":: " + pamFp.message)
            : ":: OR SCAN FINGERPRINT"
          color: pamFp.messageIsError ? Color.urgent : Color.accent
          opacity: Style.emphasis.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: Style.headerTracking
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
