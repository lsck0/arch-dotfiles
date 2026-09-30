import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

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

  // labels map to obs inputs via MUTE_SOURCES in obs-status.py
  readonly property var muteSources: ["Mic", "Chromium", "Discord", "Firefox", "Spotify", "Desktop"]
  property var mutes: ({})

  // obs reports cumulative bytes, so rates are derived here
  property real prevStreamBytes: -1
  property real prevRecordBytes: -1
  property real prevSampleMs: 0
  property real bitrateKbps: 0
  property real recordKbps: 0

  readonly property real diskSecondsLeft:
    recordKbps > 0 ? (freeDiskMb * 1024 * 8) / recordKbps : 0

  readonly property bool active: streaming || recording

  property var bitrateHist: []
  property var dropHist: []

  readonly property color stateColor: (degraded || faulted)
    ? Color.semantic.warn
    : (streaming ? Color.semantic.live : (recording ? Color.semantic.recording : Color.muted))
  readonly property bool degraded: streamReconnecting || dropPct >= 1.0 || congestion >= 0.3

  // obs runs but the helper cannot reach it
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

  function clearSession() {
    streaming = false
    streamReconnecting = false
    recording = false
    recordPaused = false
    bitrateKbps = 0
    recordKbps = 0
    prevStreamBytes = -1
    prevRecordBytes = -1
    prevSampleMs = 0
    scene = ""
    scenes = []
    mutes = ({})
  }

  function apply(payload) {
    connected = payload.connected === true
    errorText = String(payload.error || "")
    if (!connected) {
      clearSession()
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
    if (payload.mutes && typeof payload.mutes === "object") mutes = payload.mutes

    var sBytes = Number(payload.streamBytes) || 0
    var rBytes = Number(payload.recordBytes) || 0
    var nowMs = Date.now()
    var deltaS = prevSampleMs > 0 ? (nowMs - prevSampleMs) / 1000 : 0

    // only between two samples of the same session
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
    // a paused recording keeps its last rate for the disk estimate

    streamBytes = sBytes
    prevStreamBytes = sBytes
    prevRecordBytes = rBytes
    prevSampleMs = nowMs

    bitrateHist = Util.historyPush(bitrateHist, streaming ? bitrateKbps : (recording ? recordKbps : 0))
    dropHist = Util.historyPush(dropHist, dropPct)
  }

  // run the helper only while obs runs
  property bool obsSeen: false

  function probeForObs() {
    if (!obsProbe.running) obsProbe.running = true
  }

  Process {
    id: obsProbe
    // -x, pgrep -f would match its own command line
    command: ["pgrep", "-x", "obs"]
    onExited: function (exitCode) {
      root.obsSeen = exitCode === 0
    }
  }

  onObsSeenChanged: if (!obsSeen) {
    connected = false
    errorText = ""
    clearSession()
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.probeForObs() }
  }

  Timer {
    interval: root.obsSeen ? 3000 : 60000
    running: !root.obsSeen || !root.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeForObs()
  }

  // stdin is the command channel into obs
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
    // rejected commands
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

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: root.stateColor
      layer.enabled: Style.fx.glow > 0 && root.active
      layer.effect: Glow { shadowColor: root.stateColor }

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
      text: {
        if (root.faulted) return "OBS ⚠"
        if (root.streamReconnecting) return "RECONNECTING"
        if (root.streaming && root.recording) return "LIVE+REC"
        if (root.streaming) return "LIVE"
        if (root.recording) return root.recordPaused ? "REC PAUSED" : "REC"
        return "OBS"
      }
      color: root.active || root.faulted
        ? root.stateColor
        : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: root.active
      opacity: root.active || root.faulted ? 1 : 0.55
      layer.enabled: Style.fx.glow > 0 && root.active
      layer.effect: Glow { shadowColor: root.stateColor }
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
    title: "OBS"
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    component StatRow: Row {
      id: statRow
      property string label: ""
      property string value: ""
      property color valueColor: Color.menu.text
      property bool dim: false
      width: parent.width
      Text {
        width: statRow.width * 0.45
        text: statRow.label
        color: Color.menu.text
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.headerTracking * 0.4
      }
      Text {
        width: statRow.width * 0.55
        horizontalAlignment: Text.AlignRight
        text: statRow.value
        color: statRow.valueColor
        opacity: statRow.dim ? Style.emphasis.faint : 1
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: Style.displayTracking
      }
    }

    component Action: Rectangle {
      id: action
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
          text: action.glyph
          color: action.tint
          font.family: Style.font.iconFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: action.label
          color: action.tint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: actionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: action.activated()
      }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      Item {
        width: parent.width
        visible: root.connected
        implicitHeight: Math.max(obsHero.implicitHeight, obsMeta.implicitHeight)
        height: implicitHeight
        Row {
          id: obsHero
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs
          Text {
            id: heroNum
            anchors.bottom: parent.bottom
            text: root.streaming ? Math.round(root.bitrateKbps)
                : (root.recording ? Math.round(root.recordKbps) : root.fps.toFixed(0))
            color: root.active ? root.stateColor : Color.accent
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.display * 1.7)
            font.bold: true
            font.letterSpacing: Style.displayTracking
            layer.enabled: Style.fx.glow > 0
            layer.effect: Glow { shadowColor: root.active ? root.stateColor : Style.fx.glowColor }
          }
          Text {
            anchors.bottom: heroNum.bottom
            anchors.bottomMargin: Math.round(Style.font.body * 0.3)
            text: root.active ? "KBPS" : "FPS"
            color: root.active ? root.stateColor : Color.accent
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking
          }
        }
        Column {
          id: obsMeta
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.5
          spacing: Style.spacing.xxs
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: root.streamReconnecting ? "RECONNECTING"
                : (root.streaming && root.recording ? "LIVE + REC"
                : (root.streaming ? "LIVE"
                : (root.recording ? (root.recordPaused ? "REC PAUSED" : "REC") : "IDLE")))
            color: root.active ? root.stateColor : Color.menu.text
            opacity: root.active ? 1 : Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking * 0.5
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: root.active
            text: root.clock(root.streaming ? root.streamSeconds : root.recordSeconds)
            color: Color.menu.text
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: Style.displayTracking
          }
        }
      }

      Sparkline {
        width: parent.width
        height: Style.space(34)
        visible: root.connected && root.bitrateHist.length > 1
        values: root.bitrateHist
        minValue: 0
        maxValue: 0
        color: root.active ? root.stateColor : Color.accent
      }

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
          // obs rejects pause unless recording
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

      // flow so long scene lists wrap
      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.connected

        Repeater {
          model: root.scenes
          delegate: Chip {
            required property string modelData
            text: modelData
            selected: modelData === root.scene
            // already live, skip the round trip
            onClicked: if (!selected) root.send({ cmd: "setScene", scene: modelData })
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

      PanelSeparator { visible: root.connected }
      PanelSectionHeader { text: "AUDIO"; visible: root.connected }

      Flow {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.connected

        Repeater {
          model: root.muteSources
          delegate: Chip {
            required property string modelData
            readonly property bool muted: root.mutes[modelData] === true
            text: modelData
            selected: !muted
            opacity: muted ? Style.emphasis.dim : 1
            onClicked: root.send({ cmd: "toggleMute", source: modelData })
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "STATUS" }

      StatRow { label: "Scene"; value: root.scene || "--"; dim: root.scene === "" }
      StatRow { label: "Output FPS"; value: root.fps.toFixed(1) }
      StatRow { label: "Frame render"; value: root.frameTimeMs.toFixed(2) + " ms" }
      StatRow { label: "OBS CPU"; value: root.cpu.toFixed(1) + "%" }
      StatRow { label: "OBS memory"; value: root.gb(root.memMb) }

      PanelSeparator {}
      PanelSectionHeader { text: "STREAM" }

      StatRow {
        label: "State"
        value: root.streamReconnecting ? "Reconnecting"
             : (root.streaming ? "Live" : "Stopped")
        valueColor: root.streamReconnecting ? Color.semantic.warn
                  : (root.streaming ? Color.semantic.live : Color.menu.text)
        dim: !root.streaming && !root.streamReconnecting
      }
      StatRow { visible: root.streaming; label: "Elapsed"; value: root.clock(root.streamSeconds) }
      StatRow { visible: root.streaming; label: "Bitrate"; value: Math.round(root.bitrateKbps) + " kbps" }
      StatRow { visible: root.streaming; label: "Sent"; value: root.bytesText(root.streamBytes) }
      StatRow {
        visible: root.streaming
        label: "Dropped frames"
        value: root.droppedFrames + "  (" + root.dropPct.toFixed(2) + "%)"
        valueColor: root.dropPct >= 1.0 ? Color.semantic.warn : Color.menu.text
      }
      StatRow {
        visible: root.streaming
        label: "Congestion"
        value: Math.round(root.congestion * 100) + "%"
        valueColor: root.congestion >= 0.3 ? Color.semantic.warn : Color.menu.text
      }
      BarGauge {
        width: parent.width
        height: Style.spacing.md
        visible: root.streaming
        segments: 24
        value: Math.max(0, Math.min(1, root.congestion))
        color: root.congestion >= 0.3 ? Color.semantic.warn : Color.accent
      }
      Sparkline {
        width: parent.width
        height: Style.space(28)
        visible: root.streaming && root.dropHist.length > 1
        values: root.dropHist
        minValue: 0
        maxValue: 0
        color: Color.semantic.warn
      }

      PanelSeparator {}
      PanelSectionHeader { text: "RECORDING" }

      StatRow {
        label: "State"
        value: root.recordPaused ? "Paused" : (root.recording ? "Recording" : "Stopped")
        valueColor: root.recording ? Color.semantic.recording : Color.menu.text
        dim: !root.recording
      }
      StatRow { visible: root.recording; label: "Elapsed"; value: root.clock(root.recordSeconds) }
      // the recording is often encoded heavier than the stream
      StatRow { visible: root.recording; label: "Bitrate"; value: Math.round(root.recordKbps) + " kbps" }
      StatRow { visible: root.recording; label: "Written"; value: root.bytesText(root.recordBytes) }
      StatRow { label: "Disk free"; value: root.gb(root.freeDiskMb) }
      StatRow {
        visible: root.recording && root.diskSecondsLeft > 0
        label: "Disk headroom"
        value: root.clock(root.diskSecondsLeft) + " at this rate"
        valueColor: root.diskSecondsLeft < 600 ? Color.semantic.live
                  : (root.diskSecondsLeft < 3600 ? Color.semantic.warn : Color.menu.text)
      }

      PanelSeparator {}
      PanelSectionHeader { text: "SKIPPED FRAMES" }

      StatRow {
        label: "Rendering"
        value: root.renderSkipped + " / " + root.renderTotal
        valueColor: root.renderTotal > 0 && root.renderSkipped / root.renderTotal >= 0.01
          ? Color.semantic.warn : Color.menu.text
      }
      StatRow {
        label: "Encoding"
        value: root.encoderSkipped + " / " + root.encoderTotal
        valueColor: root.encoderTotal > 0 && root.encoderSkipped / root.encoderTotal >= 0.01
          ? Color.semantic.warn : Color.menu.text
      }

    }
  }
}
