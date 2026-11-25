pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root
  property bool locked: false
  property bool authError: false
  // the shell's main screen (workspace 1, then the 0,0 monitor); lock() falls back to screens[0] when unset
  property string mainScreenName: ""
  property string primaryScreenName: ""
  property string _pw: ""
  property var activeField: null
  property real lockedAtMs: 0
  property bool keyMode: false
  property string _pin: ""
  property string keyDevice: ""
  property int pinRetries: -1
  property int pinLengthMin: 4
  property string keyCue: ""
  property string keyNote: ""
  readonly property int keyProbeSettleMs: 250
  // base/pam installs the service only on a machine with a usable fingerprint sensor
  readonly property string fprintService: "/etc/pam.d/quickshell-lock-fprint"
  property bool fprintAvailable: false
  property string fprintCue: ""
  property int fprintRounds: 0
  // each round is the service's three tries; past these the finger is off until the next lock
  readonly property int fprintRoundsMax: 5
  // desktop/hyprland's dpms.nu reports the outputs through the lock IPC target
  property bool screensOn: true
  readonly property string keyStatus: {
    if (pamU2f.active) return root.keyCue !== "" ? root.keyCue : "waiting for security key"
    if (pamPw.active) return "verifying"
    var retries = root.pinRetries >= 0 ? root.pinRetries + " PIN attempts left" : ""
    if (root.keyNote !== "") return retries !== "" ? root.keyNote + ", " + retries : root.keyNote
    if (pamFprint.active) return root.fprintCue !== "" ? root.fprintCue : "fingerprint ready"
    if (root.keyMode) return retries !== "" ? "security key PIN, " + retries : "security key PIN"
    // a finger round that timed out, or was stopped by typing, is no longer listening; past the last round it stays off
    if (root.fprintAvailable)
      return root.fprintRounds >= root.fprintRoundsMax ? "fingerprint off :: type password" : "fingerprint paused :: ESC to retry"
    return ""
  }
  property string statsText: ""
  readonly property int ambientMs: 30000
  readonly property string notesDir: Paths.state + "/notifications"
  readonly property int notesShown: 3
  property var notes: []
  // only a player that plays: a paused tab or app left open is not media playing; the bar's one first, then from the
  // bar's list, so a browser tab and its plasma-browser-integration twin show the same track as the bar
  readonly property var player: {
    var shown = MediaState.player
    if (shown && shown.playbackState === MprisPlaybackState.Playing) return shown
    return MediaState.players.find(p => p.playbackState === MprisPlaybackState.Playing) || null
  }
  readonly property string mediaArtist: player ? MediaState.tag(player.trackArtist) : ""
  readonly property string mediaText: player && player.trackTitle ? "> " + (mediaArtist ? mediaArtist + " :: " : "") + player.trackTitle : ""
  // the locale's order and 12 or 24 hours (LC_TIME), in the lock's own separators: HH//mm//ss, >> dd/MM/yy
  readonly property string clockFormat: Util.timeFormat.replace(/(m+)/, "$1:ss").replace(/[:.]/g, "//")
  readonly property string dateFormat: ">> " + Qt.locale().dateFormat(Locale.ShortFormat).replace(/y+/, "yy")
    .replace(/[^A-Za-z]+/g, "/").replace(/^\/|\/$/g, "")
  property string clockText: "00//00//00"
  property string dateText: ""

  signal clearFields()
  signal authFailed()
  signal glitchOut()

  function lock() {
    if (unlockDelay.running) {
      unlockDelay.stop()
      return
    }
    if (root.locked) {
      if (sessionLock.locked) return
      root.locked = false
    }
    root.lockedAtMs = Date.now()
    root.notes = []
    root.authError = false
    root._pw = ""
    var scr = Quickshell.screens
    root.primaryScreenName = root.mainScreenName || ((scr && scr.length) ? String(scr[0].name) : "")
    root.locked = true
  }

  function unlock() {
    root.authError = false
    root._pw = ""
    root.clearFields()
    pamPw.active = false
    root.fprintDisarm()
    root.glitchOut()
    unlockDelay.restart()
  }

  function submit() {
    if (!root.locked || !root.activeField || root.activeField.text.length === 0 || pamPw.active) return
    root._pw = root.activeField.text
    root.authError = false
    root.keyNote = ""
    pamPw.start()
  }

  function fail() {
    root.authError = true
    root._pw = ""
    root.clearFields()
    root.authFailed()
  }

  function fprintArm() {
    if (!root.locked || !root.fprintAvailable || !root.screensOn || root.fprintRounds >= root.fprintRoundsMax) return
    if (pamFprint.active || pamPw.active || root.keyMode || unlockDelay.running) return
    root.fprintRounds++
    root.fprintCue = ""
    pamFprint.start()
  }

  function fprintDisarm() {
    if (pamFprint.active) pamFprint.abort()
  }

  function keyModeEnter() {
    if (!root.locked || root.keyMode || root.keyDevice === "" || pamPw.active) return
    root.fprintDisarm()
    root._pw = ""
    root.clearFields()
    root.authError = false
    root.keyNote = ""
    root.pinRetries = -1
    root.keyMode = true
    retriesProc.running = true
  }

  function keyModeLeave() {
    root.keyMode = false
    root._pin = ""
    root.keyCue = ""
    root.clearFields()
    if (pamU2f.active) pamU2f.abort()
  }

  function submitPin() {
    if (!root.locked || !root.keyMode || pamU2f.active || retriesProc.running) return
    if (!root.activeField || root.activeField.text.length === 0) return
    if (root.activeField.text.length < root.pinLengthMin) {
      root.keyNote = "PIN too short"
      root.clearFields()
      return
    }
    root._pin = root.activeField.text
    root.clearFields()
    root.keyNote = ""
    root.keyCue = ""
    pamU2f.start()
  }

  function keyFail(note) {
    root.keyModeLeave()
    root.authError = true
    root.keyNote = note
    root.authFailed()
    if (root.keyDevice !== "") retriesProc.running = true
  }

  readonly property string lockMarker: Paths.runtime + "/locked"

  onLockedChanged: {
    root.keyMode = false
    root._pin = ""
    root.keyCue = ""
    root.keyNote = ""
    root.fprintRounds = 0
    root.fprintDisarm()
    if (root.locked) {
      root.screensOn = true
      keyProbe.running = true
      fprintProbe.running = true
    }
    Quickshell.execDetached(root.locked ? ["install", "-D", "-m", "600", "/dev/null", root.lockMarker] : ["rm", "-f", root.lockMarker])
  }
  Component.onCompleted: markerProbe.running = true

  Process {
    id: markerProbe
    command: ["test", "-e", root.lockMarker]
    onExited: function(exitCode) {
      if (exitCode === 0) root.lock()
    }
  }

  onKeyDeviceChanged: {
    if (root.keyDevice === "" && root.keyMode && !pamU2f.active) {
      root.keyModeLeave()
    }
  }

  Timer {
    id: unlockDelay
    // the Glitch's run (its durationMs), 0 under the power saver
    interval: Style.motion.base
    onTriggered: root.locked = false
  }

  IpcHandler {
    function lock() : string {
      root.lock()
      return "ok"
    }

    function isLocked() : string {
      return sessionLock.secure && !unlockDelay.running ? "true" : "false"
    }

    function screens(state: string) : string {
      root.screensOn = state !== "off"
      if (root.screensOn) root.fprintArm()
      else root.fprintDisarm()
      return "ok"
    }

    target: "lock"
  }

  PamContext {
    id: pamPw
    config: "quickshell-lock"
    onResponseRequiredChanged: {
      if (responseRequired) {
        respond(root._pw)
      }
    }
    // pam_faillock says why a right password is refused (locked, minutes left), as info and in two messages
    onPamMessage: {
      if (responseRequired || message === "") return
      var line = String(message).replace(/\s+/g, " ").trim()
      root.keyNote = root.keyNote !== "" ? root.keyNote + " " + line : line
    }
    onCompleted: function(result) {
      if (result === PamResult.Success) root.unlock()
      else root.fail()
      active = false
      if (result !== PamResult.Success) root.fprintArm()
    }
    onError: function(err) {
      root.fail()
      active = false
    }
  }

  PamContext {
    id: pamU2f
    config: "quickshell-lock-u2f"
    onPamMessage: {
      if (!responseRequired) {
        if (messageIsError) root.keyNote = message
        else root.keyCue = message
        return
      }
      if (root._pin === "") {
        root.keyFail("security key asked twice")
        return
      }
      respond(root._pin)
      root._pin = ""
    }
    onCompleted: function(result) {
      if (result === PamResult.Success) root.unlock()
      else if (root.keyMode) root.keyFail("security key failed")
      active = false
    }
    onError: function(err) {
      if (root.keyMode) root.keyFail("security key failed")
      active = false
    }
  }

  PamContext {
    id: pamFprint
    config: "quickshell-lock-fprint"
    onPamMessage: {
      if (!responseRequired) root.fprintCue = message
    }
    onCompleted: function(result) {
      active = false
      if (result === PamResult.Success) root.unlock()
    }
    onError: active = false
  }

  Process {
    id: fprintProbe
    command: ["test", "-e", root.fprintService]
    onExited: function(exitCode) {
      root.fprintAvailable = exitCode === 0
      root.fprintArm()
    }
  }

  Process {
    id: keyProbe
    command: ["fido2-token", "-L"]

    stdout: StdioCollector {
      onStreamFinished: {
        var device = String(text).match(/^(\/dev\/hidraw[0-9]+):/m)
        root.keyDevice = device ? device[1] : ""
      }
    }
  }

  Timer {
    id: keyProbeSettle
    interval: root.keyProbeSettleMs
    onTriggered: {
      if (!keyProbe.running) {
        keyProbe.running = true
      }
    }
  }

  Process {
    running: root.locked
    command: ["setpriv", "--pdeathsig", "TERM", "udevadm", "monitor", "--udev", "--subsystem-match=hidraw"]

    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("(hidraw)") >= 0) keyProbeSettle.restart()
      }
    }
  }

  Process {
    id: retriesProc
    command: ["fido2-token", "-I", root.keyDevice]

    stdout: StdioCollector {
      onStreamFinished: {
        var retries = String(text).match(/^pin retries: ([0-9]+)$/m)
        var lengthMin = String(text).match(/^minpinlen: ([0-9]+)$/m)
        root.pinRetries = retries ? Number(retries[1]) : -1
        if (lengthMin) root.pinLengthMin = Number(lengthMin[1])
      }
    }
  }

  Process {
    id: statsProc
    command: ["timeout", "4s", Paths.home + "/.config/hypr/lockscreen-stats.nu"]

    stdout: StdioCollector {
      onStreamFinished: root.statsText = String(text).trim()
    }
  }

  Timer {
    interval: root.ambientMs
    running: root.locked && root.screensOn
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!statsProc.running) statsProc.running = true
      notesProc.run()
    }
  }

  JsonProcess {
    id: notesProc
    command: ["bash", "-c", "cat \"$1\"/*.json \"$1\"/history/*.json 2>/dev/null" + " | jq -s -c --argjson since \"$2\" '[.[] | select((.timestamp // 0) >= $since)" + " | {app: (.app // \"\"), timestamp}] | unique_by([.timestamp, .app]) | sort_by(-.timestamp)'", "--", root.notesDir, String(Math.floor(root.lockedAtMs))]

    onParsed: function(parsed) {
      root.notes = Util.isList(parsed) ? Array.from(parsed) : []
    }
    onFailed: root.notes = []
  }

  Timer {
    interval: 1000
    running: root.locked && root.screensOn
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var now = new Date()
      root.clockText = Qt.formatDateTime(now, root.clockFormat)
      root.dateText = Qt.formatDateTime(now, root.dateFormat)
    }
  }

  WlSessionLock {
    id: sessionLock
    locked: root.locked

    WlSessionLockSurface {
      id: surface
      readonly property bool isPrimary: root.primaryScreenName === "" || (screen && String(screen.name) === root.primaryScreenName) // qmllint disable missing-property

      function reveal() {
        pwField.forceActiveFocus()
        glitch.play()
      }

      color: Colors.background
      onVisibleChanged: if (visible) Qt.callLater(function() { surface.reveal() })
      Component.onCompleted: Qt.callLater(function() { surface.reveal() })

      Item {
        id: lockContent
        anchors.fill: parent

        Image {
          id: wallpaper
          anchors.fill: parent
          source: root.locked ? Util.fileUrl(Paths.wal + "/wallpaper") : ""
          cache: false
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
          sourceSize: {
            const dpr = surface.screen && surface.screen.devicePixelRatio ? surface.screen.devicePixelRatio : 1 // qmllint disable missing-property
            return Qt.size(surface.width * dpr, surface.height * dpr)
          }
          opacity: 0.35
          layer.enabled: true

          layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1
            blurMax: 64
          }
        }

        Rectangle {
          anchors.fill: parent

          gradient: Gradient {
            GradientStop {
              position: 0
              color: Util.alpha(Colors.background, 0.7)
            }

            GradientStop {
              position: 1
              color: Util.alpha(Colors.accent, 0.22)
            }
          }
        }

        AsciiProjection {
          anchors.fill: parent
          image: wallpaper
          active: root.locked && surface.visible
          animate: Style.fx.matrixRain > 0 && Style.motion.enabled
          paused: !root.screensOn
        }

        // whoever comes back to a locked screen moves the pointer or touches a key first; input also means the
        // outputs are on, should dpms.nu's report have been lost
        HoverHandler {
          onPointChanged: {
            root.screensOn = true
            root.fprintArm()
          }
        }

        // a shade keeps the date and hints readable where the ASCII field runs through the clock block; blurred
        // past its edges it fades into the field instead of standing in it as a box
        RectangularShadow {
          anchors.centerIn: clockBlock
          width: clockBlock.width + Style.surface.padding * 2
          height: clockBlock.height + Style.surface.padding * 2
          radius: height / 2
          blur: Style.space(112)
          color: Colors.panelFill
        }

        Column {
          id: clockBlock
          anchors.centerIn: parent
          spacing: Style.spacing.sm

          Hero {
            anchors.horizontalCenter: parent.horizontalCenter
            value: root.clockText
            size: Style.font.hero * 2
            live: true
          }

          Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            color: Colors.textOnOverlay(Colors.textDim)
            font.pixelSize: Style.font.title
            font.letterSpacing: Style.headerTracking
          }

          Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Prefs.lockMedia && root.mediaText !== ""
            width: Math.min(implicitWidth, Style.space(480))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.mediaText
            color: Colors.textOnOverlay(Colors.accentText)
          }

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(320)
            height: Style.space(46)
            color: Util.alpha(Colors.background, 0.55)
            border.width: root.authError ? Style.focusBorderWidth : Style.normalBorderWidth
            border.color: root.authError ? Colors.urgent : (pwField.activeFocus ? Colors.accent : Style.normalBorderColor)
            radius: Style.shape.data
            opacity: (pwField.text.length > 0 || root.authError || pamPw.active || root.keyMode) ? 1 : 0
            transform: Shake { id: pwShake }

            Connections {
              function onAuthFailed() {
                pwShake.play()
              }

              target: root
            }

            TextField {
              id: pwField
              anchors.fill: parent
              anchors.margins: Style.spacing.xs
              echoMode: TextInput.Password
              enabled: root.locked
              readOnly: pamPw.active
              color: "transparent"
              selectionColor: "transparent"
              selectedTextColor: "transparent"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.letterSpacing: Style.labelTracking
              horizontalAlignment: TextInput.AlignHCenter
              verticalAlignment: TextInput.AlignVCenter
              placeholderText: root.authError ? "> ACCESS DENIED" : root.keyMode ? "> KEY PIN" : "> AUTH REQUIRED"
              placeholderTextColor: root.authError ? Colors.urgentText : Colors.textDim
              background: null
              onTextEdited: {
                root.authError = false
                root.fprintDisarm()
              }
              onAccepted: {
                root.activeField = pwField
                if (root.keyMode) root.submitPin()
                else root.submit()
              }
              Keys.onEscapePressed: {
                if (root.keyMode) root.keyModeLeave()
                else text = ""
                root.fprintArm()
              }
              Keys.onPressed: function(event) {
                root.screensOn = true
                if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
                  root.keyModeEnter()
                  event.accepted = true
                }
              }

              Connections {
                function onClearFields() {
                  pwField.text = ""
                }

                target: root
              }

              cursorDelegate: Item {}
            }

            Row {
              anchors.centerIn: parent
              visible: pwField.text.length > 0
              spacing: 0

              Label {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Style.space(280))
                elide: Text.ElideLeft
                text: "*".repeat(pwField.text.length)
                font.letterSpacing: Style.labelTracking
              }

              BlinkCaret {
                anchors.verticalCenter: parent.verticalCenter
                block: true
                prompt: true
                size: Style.font.body
                running: root.locked && pwField.activeFocus
              }
            }

            Behavior on opacity {
              NumberAnimation {
                duration: Style.motion.base
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Style.motion.enter
              }
            }
          }

          Label {
            id: keyStatusText
            anchors.horizontalCenter: parent.horizontalCenter
            height: keyStatusMetrics.height
            text: root.keyStatus
            opacity: root.keyStatus !== "" ? 1 : 0
            color: Colors.textOnOverlay(root.keyNote !== "" ? Colors.urgent : Colors.textDim)
            caption: true

            FadeBehavior on opacity {}

            FontMetrics {
              id: keyStatusMetrics
              font: keyStatusText.font
            }
          }

          KeyHints {
            anchors.horizontalCenter: parent.horizontalCenter
            // the password box stays hidden until the first key, so the hint names the way in
            hints: (root.keyMode || pwField.text.length > 0 ? [["ENTER", "unlock"]] : [["TYPE", "password"]])
              .concat(root.keyDevice !== "" && !root.keyMode ? [["CTRL+K", "security key"]] : [])
              .concat(root.keyMode ? [["ESC", "password"]] : pwField.text.length > 0 ? [["ESC", "clear"]] : [])
          }
        }

        // the clock's shade, not a box: blurred past the line it fades into the field
        Item {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.lg
          visible: surface.isPrimary && root.statsText !== ""
          width: statsLine.implicitWidth
          height: statsLine.implicitHeight

          RectangularShadow {
            anchors.centerIn: parent
            width: parent.width + Style.surface.padding * 2
            height: parent.height + Style.surface.padding * 2
            radius: height / 2
            blur: Style.space(48)
            color: Colors.panelFill
          }

          Label {
            id: statsLine
            anchors.centerIn: parent
            text: root.statsText
            color: Colors.textOnOverlay(Colors.textDim)
            caption: true
          }
        }

        GlassCard {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.lg
          visible: Prefs.lockNotifications && surface.isPrimary && root.notes.length > 0
          width: notesColumn.implicitWidth + Style.surface.padding * 2
          height: notesColumn.implicitHeight + Style.surface.padding * 2
          scanlines: false

          ColumnLayout {
            id: notesColumn
            anchors.centerIn: parent
            spacing: Style.spacing.xxs

            HudTitle {
              Layout.alignment: Qt.AlignRight
              text: "notifications"
              suffix: "[" + root.notes.length + "]"
              blinking: false
            }

            Repeater {
              model: root.notes.slice(0, root.notesShown)

              Label {
                required property var modelData

                Layout.alignment: Qt.AlignRight
                text: (modelData.app || "--") + " :: " + Qt.formatDateTime(new Date(modelData.timestamp), Util.timeFormat)
                color: Colors.textOnOverlay(Colors.textDim)
                caption: true
              }
            }
          }
        }

        HudFrame {}

        Scanlines {}
      }

      Glitch {
        id: glitch
        anchors.fill: parent
        source: lockContent
      }

      Connections {
        function onGlitchOut() {
          glitch.play()
        }

        target: root
      }
    }
  }
}
