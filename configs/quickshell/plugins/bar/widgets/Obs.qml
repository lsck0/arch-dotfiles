import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. The SPEC asks for "OBS status:
// LIVE/RECORDING with stats like bitrate, dropped frames etc".
//
// The data comes from obs-status.py, a long-lived obs-websocket client read
// through a SplitParser — the same shape as System.qml/system-stats.sh rather
// than a process per sample. Its header explains why the connection details
// are read from obs-websocket's own config file and never duplicated here.
//
// PRESENCE IS THE POINT. The widget does not exist on the bar unless OBS is
// running: a permanent "OBS: not running" chip is a line of noise 99% of the
// time. Once OBS is up it shows idle state, and when an output starts it
// becomes the loudest thing in the bar, because going live without noticing —
// or, worse, believing you are live when the stream dropped — is the failure
// this widget exists to prevent.
//
// Glyphs verified BY NAME against the 0xProto Nerd Font cmap: md-record
// U+F044A, md-video U+F0567, md-pause U+F03E4, md-alert_circle U+F0028,
// md-speedometer U+F04C5, md-harddisk U+F02CA, md-movie_open U+F0FCE.
BarWidget {
  id: root
  moduleName: "obs"

  property bool connected: false
  property string errorText: ""
  property bool streaming: false
  property bool streamReconnecting: false
  property bool recording: false
  property bool recordPaused: false
  property int streamSeconds: 0
  property int recordSeconds: 0
  property real streamBytes: 0
  property real recordBytes: 0
  property real congestion: 0
  property int droppedFrames: 0
  property int totalFrames: 0
  property real dropPct: 0
  property real fps: 0
  property real cpu: 0
  property real memMb: 0
  property real freeDiskMb: 0
  property real frameTimeMs: 0
  property int renderSkipped: 0
  property int renderTotal: 0
  property int encoderSkipped: 0
  property int encoderTotal: 0
  property string scene: ""
  property var scenes: []

  // Live bitrates, derived here rather than read from OBS: obs-websocket
  // reports cumulative session bytes, not a rate. Two successive samples and
  // the wall time between them is the whole calculation, and doing it in the
  // widget keeps the helper stateless.
  //
  // Streaming and recording are tracked SEPARATELY because they are separate
  // outputs with separate encoders — a local recording is routinely a much
  // higher bitrate than the stream going out, and the two run at the same time
  // often enough that one number for both would be wrong in whichever mode you
  // happened to care about.
  property real prevStreamBytes: -1
  property real prevRecordBytes: -1
  property real prevSampleMs: 0
  property real bitrateKbps: 0
  property real recordKbps: 0

  // How long the free disk lasts at the current recording rate. The one number
  // that turns "333 GB free" into something actionable mid-session.
  readonly property real diskSecondsLeft:
    recordKbps > 0 ? (freeDiskMb * 1024 * 8) / recordKbps : 0

  readonly property bool active: streaming || recording

  // The state colour, used by the dot AND the label. Streaming outranks
  // recording: if both outputs are running, the one with an audience is the
  // one you must not lose track of.
  readonly property color stateColor: (degraded || faulted)
    ? Color.semantic.warn
    : (streaming ? Color.semantic.live : (recording ? Color.semantic.recording : Color.muted))
  // Reconnecting is the state worth shouting about: the bar still says LIVE
  // while the stream is, in fact, not reaching anyone.
  readonly property bool degraded: streamReconnecting || dropPct >= 1.0 || congestion >= 0.3

  // OBS IS RUNNING BUT THE HELPER CANNOT TALK TO IT — obs-websocket switched
  // off, a password this side does not have, the python module missing. The
  // helper goes to some trouble to distinguish those and report which; that
  // was wasted, because `visible: connected` hid the widget in exactly the
  // cases it had something to say, panel and all. So the error reports itself.
  //
  // Gated on `obsSeen`, so a machine that never opens OBS still gets no chip:
  // the helper is not even started until `pgrep -x obs` succeeds, and a
  // permanent "OBS: disabled" on a bar belonging to someone who does not
  // stream is precisely the noise this widget's header rejects.
  readonly property bool faulted: obsSeen && !connected && errorText !== ""

  visible: connected || faulted

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  function clock(seconds) {
    var total = Math.max(0, Math.floor(seconds))
    var h = Math.floor(total / 3600)
    var m = Math.floor((total % 3600) / 60)
    var s = total % 60
    var mm = String(m).padStart(2, "0")
    var ss = String(s).padStart(2, "0")
    return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
  }

  function gb(mb) {
    var v = Number(mb) || 0
    return v >= 1024 ? (v / 1024).toFixed(1) + " GB" : Math.round(v) + " MB"
  }

  function bytesText(bytes) {
    var v = Number(bytes) || 0
    if (v >= 1073741824) return (v / 1073741824).toFixed(2) + " GB"
    if (v >= 1048576) return (v / 1048576).toFixed(0) + " MB"
    return Math.round(v / 1024) + " KB"
  }

  function apply(payload) {
    connected = payload.connected === true
    errorText = String(payload.error || "")
    if (!connected) {
      streaming = false
      recording = false
      bitrateKbps = 0
      recordKbps = 0
      prevStreamBytes = -1
      prevRecordBytes = -1
      return
    }

    streaming = payload.streaming === true
    streamReconnecting = payload.streamReconnecting === true
    recording = payload.recording === true
    recordPaused = payload.recordPaused === true
    streamSeconds = Number(payload.streamSeconds) || 0
    recordSeconds = Number(payload.recordSeconds) || 0
    recordBytes = Number(payload.recordBytes) || 0
    congestion = Number(payload.congestion) || 0
    droppedFrames = Number(payload.droppedFrames) || 0
    totalFrames = Number(payload.totalFrames) || 0
    dropPct = Number(payload.dropPct) || 0
    fps = Number(payload.fps) || 0
    cpu = Number(payload.cpu) || 0
    memMb = Number(payload.memMb) || 0
    freeDiskMb = Number(payload.freeDiskMb) || 0
    frameTimeMs = Number(payload.frameTimeMs) || 0
    renderSkipped = Number(payload.renderSkipped) || 0
    renderTotal = Number(payload.renderTotal) || 0
    encoderSkipped = Number(payload.encoderSkipped) || 0
    encoderTotal = Number(payload.encoderTotal) || 0
    scene = String(payload.scene || "")
    if (Array.isArray(payload.scenes)) scenes = payload.scenes

    var sBytes = Number(payload.streamBytes) || 0
    var rBytes = Number(payload.recordBytes) || 0
    var nowMs = Date.now()
    var deltaS = prevSampleMs > 0 ? (nowMs - prevSampleMs) / 1000 : 0

    // Only between two samples of the SAME session. Restarting an output resets
    // its byte counter, and differencing across that reset yields a large
    // negative rate; ignoring the decrease and re-baselining is correct.
    function rate(now, prev) {
      if (prev < 0 || now < prev || deltaS <= 0.2) return -1
      return Math.max(0, (now - prev) * 8 / 1000 / deltaS)
    }

    if (streaming) {
      var sRate = rate(sBytes, prevStreamBytes)
      if (sRate >= 0) bitrateKbps = sRate
    } else {
      bitrateKbps = 0
    }

    if (recording && !recordPaused) {
      var rRate = rate(rBytes, prevRecordBytes)
      if (rRate >= 0) recordKbps = rRate
    } else if (!recording) {
      recordKbps = 0
    }
    // A paused recording deliberately keeps its last rate rather than decaying
    // to zero: the disk estimate below is about what resuming will cost, and
    // zeroing it would read as "infinite headroom" at exactly the wrong moment.

    streamBytes = sBytes
    prevStreamBytes = sBytes
    prevRecordBytes = rBytes
    prevSampleMs = nowMs
  }

  // Start the helper only once OBS is actually running, and never stop it
  // after that.
  //
  // The helper is a Python process — ~13 MB of resident memory for something
  // that, on a normal day, sits in a reconnect loop against a program that is
  // not running. Holding that for the life of the shell is exactly the kind of
  // always-on cost a status widget should not impose.
  //
  // DETECTION IS BY PROCESS, NOT BY WINDOW. The obvious cheap answer is
  // ToplevelManager: no fork, no timer, fires the instant a window maps. It
  // does not work here. Measured on this machine with OBS open and recording,
  // OBS's only mapped toplevel was a CEF browser-source dialog whose appId and
  // class are both the EMPTY STRING — and the main window was not mapped at
  // all, because OBS was sitting in the tray. An appId match would have found
  // nothing while OBS was demonstrably running.
  //
  // So: `pgrep -x obs`, triggered on shell start, on any toplevel change (a
  // free, event-driven hint that something launched), and on a slow fallback
  // timer for the tray-only case where no window ever appears. All three stop
  // the moment OBS is found, and the helper then stays up for the session —
  // OBS minimised back to the tray must not blind the widget.
  property bool obsSeen: false

  function probeForObs() {
    if (obsSeen) return
    if (!obsProbe.running) obsProbe.running = true
  }

  Process {
    id: obsProbe
    // -x so it cannot match this very command line, the trap Appendix A
    // records for `pgrep -f`.
    command: ["pgrep", "-x", "obs"]
    onExited: function (exitCode) {
      if (exitCode === 0) root.obsSeen = true
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.probeForObs() }
  }

  Timer {
    // Only until OBS is found. One fork a minute while it is closed, none
    // afterwards.
    interval: 60000
    running: !root.obsSeen
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeForObs()
  }

  // The helper's stdin is the command channel back into OBS — see its header.
  // One already-authenticated session carries both directions, so a button
  // press is a single request rather than a fresh websocket handshake.
  function send(command) {
    if (!statusProc.running) return
    statusProc.write(JSON.stringify(command) + "\n")
  }

  Process {
    id: statusProc
    running: root.obsSeen
    stdinEnabled: true
    command: [Paths.barWidget("obs-status.py")]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        if (!line) return
        try {
          root.apply(JSON.parse(line))
        } catch (e) {}
      }
    }
    // The helper reports a rejected command here — an OBS request that came
    // back with result: false. Surfaced rather than swallowed: a control that
    // silently does nothing is the worst kind, and this is the only place the
    // reason exists.
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function (line) { if (line) console.warn(line) }
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    // The state dot. Red while live, amber while merely recording, dim while
    // OBS is open and doing nothing. It pulses only when something is actually
    // being captured — a permanently blinking bar item stops being a signal.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      // Recording red and live red are the convention every camera and every
      // broadcast desk already uses; this is the same deliberate exception to
      // the palette that the weather awareness colours are.
      color: root.stateColor

      SequentialAnimation on opacity {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0;  duration: 800; easing.type: Easing.InOutQuad }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      // Streaming wins the label, and says so even while also recording.
      // "REC" while live would understate it: a dropped recording costs a
      // file, a dropped stream costs the audience.
      text: {
        if (root.faulted) return "OBS ⚠"
        if (root.streamReconnecting) return "RECONNECTING"
        if (root.streaming && root.recording) return "LIVE+REC"
        if (root.streaming) return "LIVE"
        if (root.recording) return root.recordPaused ? "REC PAUSED" : "REC"
        return "OBS"
      }
      // Tinted to the state, not left on the bar foreground. The dot alone was
      // the only thing separating "live" from "recording" at a glance, and a
      // 8px dot is not enough to carry that difference.
      color: root.active || root.faulted
        ? root.stateColor
        : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: root.active
      opacity: root.active || root.faulted ? 1 : 0.55
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: root.active
      text: root.clock(root.streaming ? root.streamSeconds : root.recordSeconds)
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      opacity: Style.emphasis.dim
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    // Same label/value row as System.qml's panel. Duplicated rather than
    // hoisted into Ui/: it is nine lines, and the two panels have already
    // drifted apart once on alignment.
    component Row_: Row {
      property string label: ""
      property string value: ""
      property color valueColor: Color.menu.text
      property bool dim: false
      width: parent.width
      Text {
        width: parent.width * 0.45
        text: parent.label
        color: Color.menu.text
        opacity: Style.emphasis.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width * 0.55
        horizontalAlignment: Text.AlignRight
        text: parent.value
        color: parent.valueColor
        opacity: parent.dim ? 0.4 : 1
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    // A labelled button. PanelActionButton is icon-first and sizes itself to a
    // square; these need a glyph *and* a word, because "stop" is the one
    // control in this panel where guessing wrong is expensive.
    component Action: Rectangle {
      property string glyph: ""
      property string label: ""
      property color tint: Color.menu.text
      property bool danger: false
      signal activated()
      height: Style.row.control
      radius: Style.cornerRadius
      color: actionMouse.containsMouse
        ? Util.alpha(tint, danger ? 0.28 : 0.20)
        : Util.alpha(tint, danger ? 0.16 : 0.10)
      Behavior on color { ColorAnimation { duration: 100 } }

      Row {
        anchors.centerIn: parent
        spacing: Style.spacing.xs
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: parent.parent.glyph
          color: parent.parent.tint
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: parent.parent.label
          color: parent.parent.tint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: actionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: parent.activated()
      }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader { text: "OBS" }

      // AT THE TOP, NOT THE BOTTOM. This used to be the last child of the
      // panel, under five sections of readouts — and unreachable anyway, since
      // the widget hid itself whenever there was an error to report. When the
      // helper cannot reach OBS this line is the only content that means
      // anything, so it leads.
      Rectangle {
        width: parent.width
        height: faultText.implicitHeight + Style.spacing.sm * 2
        radius: Style.cornerRadius
        visible: root.errorText !== ""
        color: Util.alpha(Color.semantic.warn, 0.16)

        Text {
          id: faultText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.spacing.md
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.errorText
          color: Color.semantic.warn
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // --- controls ---
      //
      // First, above the readouts. The reason to open this panel mid-session is
      // almost always to act, not to read: scrolling past five rows of stats to
      // reach "stop recording" is the wrong shape for a control surface.
      //
      // Deliberately no confirmation dialog on stop. A stop is recoverable (the
      // file is kept, the stream can be restarted) and a modal between the user
      // and "stop streaming" is its own hazard.
      // Hidden, not dimmed, while the helper has no session: every one of these
      // sends a command down a pipe nothing is reading. A control that silently
      // does nothing is the worst kind — this file's own words, a few lines
      // down, about the pause button.
      Row {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.connected

        Action {
          width: (parent.width - Style.spacing.sm * 2) / 3
          glyph: root.streaming ? "\u{f1721}" : "\u{f1720}"   // md-broadcast_off / md-broadcast
          label: root.streaming ? "Stop" : "Go live"
          tint: root.streaming ? Color.semantic.live : Color.menu.text
          danger: root.streaming
          onActivated: root.send({ cmd: "toggleStream" })
        }

        Action {
          width: (parent.width - Style.spacing.sm * 2) / 3
          glyph: root.recording ? "\u{f04db}" : "\u{f044a}"   // md-stop / md-record
          label: root.recording ? "Stop rec" : "Record"
          tint: root.recording ? Color.semantic.live : Color.menu.text
          danger: root.recording
          onActivated: root.send({ cmd: "toggleRecord" })
        }

        Action {
          width: (parent.width - Style.spacing.sm * 2) / 3
          // Only meaningful while recording, and OBS rejects it otherwise, so
          // it is dimmed and inert rather than silently failing.
          //
          // Note that OBS itself decides whether a pause sticks. Measured on
          // this machine: ToggleRecordPause returns result: true with
          // outputPaused: true, and a second later the recording reports
          // running again — some recording configurations simply do not
          // support pausing, and OBS reports success anyway. Nothing to fix on
          // this side; the 1s poll will show the real state either way.
          opacity: root.recording ? 1 : 0.35
          enabled: root.recording
          glyph: root.recordPaused ? "\u{f040a}" : "\u{f03e4}"   // md-play / md-pause
          label: root.recordPaused ? "Resume" : "Pause"
          tint: root.recordPaused ? Color.semantic.recording : Color.menu.text
          onActivated: if (root.recording) root.send({ cmd: "toggleRecordPause" })
        }
      }

      PanelSeparator { visible: root.connected }
      PanelSectionHeader { text: "SCENES"; visible: root.connected }

      // Flow, not a Row: scene names are user-chosen and there are seven here.
      // A single row would either overflow the card or elide every label into
      // uselessness, and a switcher you cannot read the labels of is not one.
      Flow {
        width: parent.width
        spacing: Style.spacing.xs
        visible: root.connected

        Repeater {
          model: root.scenes
          delegate: Rectangle {
            required property string modelData
            readonly property bool current: modelData === root.scene
            height: Style.row.control
            width: sceneLabel.implicitWidth + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: current ? Color.menu.selectedBackground
                 : (sceneMouse.containsMouse ? Style.hoverFill : "transparent")
            border.width: current ? 0 : Style.normalBorderWidth
            border.color: Util.alpha(Color.menu.text, 0.18)

            Text {
              id: sceneLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: modelData
              color: parent.current ? Color.menu.selectedText : Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: sceneMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // Switching to the scene already live is a no-op in OBS, but
              // sending it anyway would still cost a round trip and a re-poll.
              onClicked: if (!parent.current) root.send({ cmd: "setScene", scene: modelData })
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.connected && root.scenes.length === 0
        text: "No scenes reported"
        color: Color.menu.text
        opacity: Style.emphasis.disabled
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      PanelSeparator {}
      PanelSectionHeader { text: "STATUS" }

      Row_ { label: "Scene"; value: root.scene || "—"; dim: root.scene === "" }
      Row_ { label: "Output FPS"; value: root.fps.toFixed(1) }
      Row_ { label: "Frame render"; value: root.frameTimeMs.toFixed(2) + " ms" }
      Row_ { label: "OBS CPU"; value: root.cpu.toFixed(1) + "%" }
      Row_ { label: "OBS memory"; value: root.gb(root.memMb) }

      PanelSeparator {}
      PanelSectionHeader { text: "STREAM" }

      Row_ {
        label: "State"
        value: root.streamReconnecting ? "Reconnecting"
             : (root.streaming ? "Live" : "Stopped")
        valueColor: root.streamReconnecting ? Color.semantic.warn
                  : (root.streaming ? Color.semantic.live : Color.menu.text)
        dim: !root.streaming && !root.streamReconnecting
      }
      // Stream and recording each show their own elapsed time. They start at
      // different moments more often than not, and the bar can only afford one
      // clock, so the panel is where the pair has to be readable.
      Row_ { visible: root.streaming; label: "Elapsed"; value: root.clock(root.streamSeconds) }
      Row_ { visible: root.streaming; label: "Bitrate"; value: Math.round(root.bitrateKbps) + " kbps" }
      Row_ { visible: root.streaming; label: "Sent"; value: root.bytesText(root.streamBytes) }
      Row_ {
        visible: root.streaming
        label: "Dropped frames"
        // The percentage is the number that matters; the raw count is there so
        // "0.4%" can be checked against "is that 4 frames or 4000".
        value: root.droppedFrames + "  (" + root.dropPct.toFixed(2) + "%)"
        valueColor: root.dropPct >= 1.0 ? Color.semantic.warn : Color.menu.text
      }
      Row_ {
        visible: root.streaming
        label: "Congestion"
        value: Math.round(root.congestion * 100) + "%"
        valueColor: root.congestion >= 0.3 ? Color.semantic.warn : Color.menu.text
      }

      PanelSeparator {}
      PanelSectionHeader { text: "RECORDING" }

      Row_ {
        label: "State"
        value: root.recordPaused ? "Paused" : (root.recording ? "Recording" : "Stopped")
        valueColor: root.recording ? Color.semantic.recording : Color.menu.text
        dim: !root.recording
      }
      Row_ { visible: root.recording; label: "Elapsed"; value: root.clock(root.recordSeconds) }
      // Recording gets its own bitrate, not the stream's: the local file is
      // routinely encoded far heavier than what goes out to the platform, and
      // while both outputs run the two numbers are genuinely different.
      Row_ { visible: root.recording; label: "Bitrate"; value: Math.round(root.recordKbps) + " kbps" }
      Row_ { visible: root.recording; label: "Written"; value: root.bytesText(root.recordBytes) }
      Row_ { label: "Disk free"; value: root.gb(root.freeDiskMb) }
      // The number that makes "333 GB free" mean something mid-session. Only
      // once there is a measured rate to divide by — before that it would be
      // an estimate built on nothing.
      Row_ {
        visible: root.recording && root.diskSecondsLeft > 0
        label: "Disk headroom"
        value: root.clock(root.diskSecondsLeft) + " at this rate"
        valueColor: root.diskSecondsLeft < 600 ? Color.semantic.live
                  : (root.diskSecondsLeft < 3600 ? Color.semantic.warn : Color.menu.text)
      }

      PanelSeparator {}
      PanelSectionHeader { text: "SKIPPED FRAMES" }

      // Render and encode skips are separate rows because they have separate
      // causes and separate fixes: render skips mean the machine cannot draw
      // the scene fast enough, encode skips mean it cannot encode it fast
      // enough. Summing them hides which.
      Row_ {
        label: "Rendering"
        value: root.renderSkipped + " / " + root.renderTotal
        valueColor: root.renderTotal > 0 && root.renderSkipped / root.renderTotal >= 0.01
          ? Color.semantic.warn : Color.menu.text
      }
      Row_ {
        label: "Encoding"
        value: root.encoderSkipped + " / " + root.encoderTotal
        valueColor: root.encoderTotal > 0 && root.encoderSkipped / root.encoderTotal >= 0.01
          ? Color.semantic.warn : Color.menu.text
      }

    }
  }
}
