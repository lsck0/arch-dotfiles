import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
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
  // notifications that arrived since this
  property real lockedAtMs: 0

  function lock() {
    // a lock during the unlock glitch cancels the unlock
    if (unlockDelay.running) { unlockDelay.stop(); return }
    if (root.locked) {
      // held or still pending: an unlock before the compositor confirms is a protocol error that kills quickshell
      if (sessionLock.locked) return
      // the compositor refused or dropped the lock: re-arm it rather than stay unlocked behind locked == true
      root.locked = false
    }
    root.lockedAtMs = Date.now()
    root.notes = []
    root.authError = false
    root._pw = ""
    var scr = Quickshell.screens
    root.primaryScreenName = (scr && scr.length) ? String(scr[0].name) : ""
    root.locked = true
  }

  // only a successful pam result may call this; the glitch plays out first, then the lock drops
  function unlock() {
    root.authError = false
    root._pw = ""
    root.clearFields()
    pamPw.active = false
    root.glitchOut()
    unlockDelay.restart()
  }

  signal glitchOut()

  Timer {
    id: unlockDelay
    // Glitch.durationMs; instant when motion is off
    interval: Style.motion.enabled ? 180 : 0
    onTriggered: root.locked = false
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
    // the compositor-granted state, not the request: the launcher falls back to hyprlock on it; a pending unlock
    // counts as unlocked so the launcher still sends its lock, which cancels it
    function isLocked(): string { return sessionLock.secure && !unlockDelay.running ? "true" : "false" }
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
  // stats and the notification dock are ambient, not live
  readonly property int ambientMs: 30000
  Timer {
    interval: root.ambientMs
    running: root.locked
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!statsProc.running) statsProc.running = true
      if (!notesProc.running) notesProc.running = true
    }
  }

  // notification dock: app and time only, summaries and bodies never reach the lock screen
  readonly property string notesDir: Paths.state + "/notifications"
  readonly property int notesShown: 3
  property var notes: []
  Process {
    id: notesProc
    command: ["bash", "-c",
      "cat \"$1\"/*.json \"$1\"/history/*.json 2>/dev/null"
      + " | jq -s -c --argjson since \"$2\" '[.[] | select((.timestamp // 0) >= $since)"
      + " | {app: (.app // \"\"), timestamp}] | unique_by([.timestamp, .app]) | sort_by(-.timestamp)'",
      "--", root.notesDir, String(Math.floor(root.lockedAtMs))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "[]")
          root.notes = Array.isArray(parsed) ? parsed : []
        } catch (e) {
          root.notes = []
        }
      }
    }
  }

  // the playing player, else the first one with a title
  readonly property var player: {
    var list = Mpris.players.values
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      if (list[i].playbackState === MprisPlaybackState.Playing) return list[i]
      if (!fallback && list[i].trackTitle) fallback = list[i]
    }
    return fallback
  }
  readonly property string mediaText: player && player.trackTitle
    ? (player.playbackState === MprisPlaybackState.Playing ? "> " : "|| ")
      + (player.trackArtist ? player.trackArtist + " :: " : "") + player.trackTitle
    : ""

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
    id: sessionLock
    locked: root.locked

    // projection and the auth hud on every screen: hyprland gives the keyboard to the surface under the cursor
    WlSessionLockSurface {
      id: surface
      color: Color.background

      readonly property bool isPrimary:
        root.primaryScreenName === "" || (screen && String(screen.name) === root.primaryScreenName)

      // what the glitch captures
      Item {
        id: lockContent
        anchors.fill: parent

        // faint blurred wallpaper; unset while unlocked so each lock decodes the current one
        Image {
          id: wallpaper
          anchors.fill: parent
          source: root.locked ? Util.fileUrl(Quickshell.env("HOME") + "/.cache/wal/wallpaper") : ""
          cache: false
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
          sourceSize: { var dpr = surface.screen && surface.screen.devicePixelRatio ? surface.screen.devicePixelRatio : 1; return Qt.size(surface.width * dpr, surface.height * dpr) }
          opacity: 0.35
          layer.enabled: true
          layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 64
          }
        }

        // theme wash: the dim wallpaper alone reads as a washed photo, this ties the lock to the pywal palette
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.7) }
            GradientStop { position: 1.0; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) }
          }
        }

        AsciiProjection {
          id: projection
          anchors.fill: parent
          image: wallpaper
          active: root.locked && surface.visible
          animate: Style.fx.matrixRain > 0 && Style.motion.enabled
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.spacing.sm

          // the lock's hero is twice the shell's
          Hero {
            anchors.horizontalCenter: parent.horizontalCenter
            value: root.clockText
            size: Style.font.hero * 2
            live: true
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

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.mediaText !== ""
            width: Math.min(implicitWidth, Style.space(480))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.mediaText
            color: Color.accent
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(320)
            height: Style.space(46)
            color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.55)
            border.width: root.authError ? 2 : 1
            border.color: root.authError ? Color.urgent
              : (pwField.activeFocus ? Color.accent : Style.normalBorderColor)
            radius: Style.shape.data
            // hidden until typing starts; keeps focus, so the first key still lands in the field
            opacity: (pwField.text.length > 0 || root.authError || pamPw.active) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }

            // the field takes input but draws nothing; the row below shows one * per char and a block cursor
            TextField {
              id: pwField
              anchors.fill: parent
              anchors.margins: Style.spacing.xs
              echoMode: TextInput.Password
              enabled: root.locked
              color: "transparent"
              selectionColor: "transparent"
              selectedTextColor: "transparent"
              cursorDelegate: Item {}
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.letterSpacing: Style.headerTracking * 0.5
              horizontalAlignment: TextInput.AlignHCenter
              verticalAlignment: TextInput.AlignVCenter
              placeholderText: root.authError ? "  ACCESS DENIED" : "> AUTH REQUIRED"
              placeholderTextColor: root.authError ? Color.urgent : Qt.darker(Color.foreground, 1.6)
              background: null
              onTextEdited: { root.authError = false; projection.ripple() }
              onAccepted: { root.activeField = pwField; root.submit() }
              Keys.onEscapePressed: text = ""
              Connections {
                target: root
                function onClearFields() { pwField.text = "" }
              }
            }

            Row {
              anchors.centerIn: parent
              visible: pwField.text.length > 0
              spacing: 0

              Text {
                anchors.verticalCenter: parent.verticalCenter
                // capped so a long passphrase never outgrows the box
                width: Math.min(implicitWidth, Style.space(280))
                elide: Text.ElideLeft
                textFormat: Text.PlainText
                text: "*".repeat(pwField.text.length)
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.letterSpacing: Style.headerTracking * 0.5
              }
              BlinkCaret {
                anchors.verticalCenter: parent.verticalCenter
                block: true
                prompt: true
                size: Style.font.body
                running: root.locked && pwField.activeFocus
              }
            }
          }
        }

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.lg
          visible: surface.isPrimary
          textFormat: Text.PlainText
          text: root.statsText
          color: Color.foreground
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // dock: how many arrived while locked and the last few apps, never their content
        Column {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.lg
          visible: surface.isPrimary && root.notes.length > 0
          spacing: Style.spacing.xxs

          HudTitle {
            anchors.right: parent.right
            text: "notifications"
            suffix: "[" + root.notes.length + "]"
            blinking: false
          }

          Repeater {
            model: root.notes.slice(0, root.notesShown)
            Text {
              required property var modelData
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: (modelData.app || "--") + " :: " + Qt.formatDateTime(new Date(modelData.timestamp), "HH:mm")
              color: Color.foreground
              opacity: Style.emphasis.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        HudFrame {}
        Scanlines {}
      }

      // one glitch as the lock comes up and one on the way out
      Glitch {
        id: glitch
        anchors.fill: parent
        source: lockContent
      }

      Connections {
        target: root
        function onGlitchOut() { glitch.play() }
      }

      onVisibleChanged: if (visible) Qt.callLater(function() { pwField.forceActiveFocus(); glitch.play() })
      Component.onCompleted: Qt.callLater(function() { pwField.forceActiveFocus(); glitch.play() })
    }
  }
}
