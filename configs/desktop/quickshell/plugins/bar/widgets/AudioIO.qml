import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// output button in the bar; the panel is the mixer: devices, loudness lanes, per-app faders and routing, what obs taps
BarWidget {
  id: root
  moduleName: "audio-io"

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0

  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool micMuted: source && source.audio ? source.audio.muted : true

  // meters, per-app binds and lane reads only exist while the panel shows
  readonly property bool live: panel.shown

  // stream whose route chooser is open
  property int routingStreamId: -1

  // lane fader positions by lane name: stream keeps music a bed under voice, chill lets it lead
  readonly property var presets: [
    { label: "STREAM", faders: { media: 0.55, voice: 1.0 } },
    { label: "CHILL", faders: { media: 1.0, voice: 0.85 } }
  ]
  // a preset reads as active within this volume distance
  readonly property real presetTolerance: 0.02

  PwObjectTracker {
    objects: [root.sink, root.source].filter(n => !!n)
      .concat(root.live ? Audio.lanes.concat(Audio.appStreams, Audio.micListeners) : [])
  }

  visible: sink !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  readonly property bool deafened: muted && micMuted

  // undeafen unmutes both, not the prior state
  function toggleDeafen() {
    var target = !deafened
    if (sink && sink.audio) sink.audio.muted = target
    if (source && source.audio) source.audio.muted = target
  }

  function laneKey(lane) { return lane.name.substring(Audio.lanePrefix.length) }

  function presetActive(preset) {
    var matched = false
    for (var i = 0; i < Audio.lanes.length; i++) {
      var lane = Audio.lanes[i]
      var want = preset.faders[laneKey(lane)]
      if (want === undefined || !lane.audio) continue
      if (Math.abs(lane.audio.volume - want) > presetTolerance) return false
      matched = true
    }
    return matched
  }

  function presetApply(label) {
    var preset = presets.find(p => p.label === label)
    if (!preset) return
    for (var i = 0; i < Audio.lanes.length; i++) {
      var want = preset.faders[laneKey(Audio.lanes[i])]
      if (want !== undefined && Audio.lanes[i].audio) Audio.lanes[i].audio.volume = want
    }
  }

  readonly property string activePreset: {
    for (var i = 0; i < presets.length; i++) if (presetActive(presets[i])) return presets[i].label
    return ""
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Audio.volumeIcon(root.volume, root.muted)
    tooltipText: root.muted ? "Muted" : Math.round(root.volume * 100) + "%  " + Audio.dbText(root.volume) + " dB"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleMute()
    }
    onWheelMoved: function(delta) { Audio.nudge(root.sink, delta) }
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  /*
   * ---------------------------------------------------------------------------
   * PANEL PARTS
   * ---------------------------------------------------------------------------
   */

  component Caption: Text {
    textFormat: Text.PlainText
    color: Color.menu.text
    elide: Text.ElideRight
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  // small outlined label: role, OBS, lane state
  component Tag: Rectangle {
    id: tag
    property string text: ""
    property color tint: Color.accent
    implicitWidth: tagLabel.implicitWidth + Style.spacing.sm * 2
    implicitHeight: tagLabel.implicitHeight + Style.spacing.xxs * 2
    radius: Style.shape.data
    color: Util.alpha(tint, 0.16)
    border.color: Util.alpha(tint, 0.6)
    border.width: Style.spacing.hair
    Text {
      id: tagLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tag.text
      color: tag.tint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.capitalization: Font.AllUppercase
    }
  }

  // section title left, extras right
  component SectionHead: Item {
    id: head
    property string text: ""
    default property alias extras: extrasRow.data
    width: parent ? parent.width : 0
    implicitHeight: Math.max(headTitle.implicitHeight, extrasRow.implicitHeight)
    PanelSectionHeader {
      id: headTitle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: head.text
    }
    Row {
      id: extrasRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs
    }
  }

  // live level of a node, dbfs scaled; the capture stream behind it exists only while active
  component Meter: Item {
    id: meter
    property var node: null
    property bool active: false
    implicitHeight: Style.spacing.xs
    PwNodePeakMonitor {
      id: monitor
      node: meter.node
      enabled: meter.active && meter.node !== null
    }
    readonly property real levelDb: Audio.db(monitor.peak)
    BarGauge {
      anchors.fill: parent
      segments: 32
      value: meter.active ? Audio.meterPosition(monitor.peak) : 0
      // dBFS: -9 hot, -3 close, -1 clipping
      color: Util.level(meter.levelDb, [-9, -3, -1])
    }
  }

  // mute glyph, cubic fader, db readout
  component Fader: Item {
    id: fader
    property var node: null
    property QtObject host: null
    property string glyph: "\u{f057e}"
    property string mutedGlyph: "\u{f075f}"
    readonly property bool muted: node && node.audio ? node.audio.muted : false
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    implicitHeight: slider.implicitHeight

    function toggleMute() {
      if (node && node.audio) node.audio.muted = !node.audio.muted
    }

    Text {
      id: muteGlyph
      width: Style.space(24)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: fader.muted ? fader.mutedGlyph : fader.glyph
      color: fader.muted ? Color.urgent : Color.menu.text
      font.family: Style.font.iconFamily
      font.pixelSize: Style.font.icon
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: fader.toggleMute()
      }
    }

    Slider {
      id: slider
      anchors.left: muteGlyph.right
      anchors.right: readout.left
      anchors.leftMargin: Style.spacing.sm
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      bar: fader.host ? fader.host.bar : null
      value: fader.volume
      fillColor: fader.muted ? Color.urgent : (bar ? bar.barForeground : Color.foreground)
      onMoved: function(v) { if (fader.node && fader.node.audio) fader.node.audio.volume = v }
      onRightClicked: fader.toggleMute()
    }

    Caption {
      id: readout
      width: Style.space(58)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: fader.muted ? "MUTE" : Audio.dbText(fader.volume) + " dB"
      color: fader.muted ? Color.urgent : Color.menu.text
    }
  }

  // one app: identity, role, obs tap, route, fader, meter
  component StreamRow: Column {
    id: stream
    required property var modelData
    property QtObject host: null
    readonly property var node: modelData
    readonly property var target: Audio.sinkOf(node)
    readonly property bool onStream: Audio.isTappedByObs(node)
    readonly property bool routing: host !== null && host.routingStreamId === node.id

    width: parent ? parent.width : 0
    spacing: Style.spacing.xs

    Item {
      width: parent.width
      implicitHeight: Math.max(appIcon.height, routeChip.implicitHeight)

      IconImage {
        id: appIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: Style.font.icon + Style.spacing.sm
        source: Audio.appIcon(stream.node)
      }

      Text {
        anchors.left: appIcon.right
        anchors.leftMargin: Style.spacing.sm
        anchors.right: tags.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: Audio.appName(stream.node)
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Row {
        id: tags
        anchors.right: routeChip.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs
        Tag { visible: stream.onStream; text: "OBS"; tint: Color.semantic.live }
      }

      Chip {
        id: routeChip
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Style.space(150))
        text: "> " + Audio.deviceName(stream.target)
        selected: stream.routing
        onClicked: stream.host.routingStreamId = stream.routing ? -1 : stream.node.id
      }
    }

    Fader {
      width: parent.width
      node: stream.node
      host: stream.host
    }

    Meter {
      width: parent.width
      node: stream.node
      active: stream.host !== null && stream.host.live
    }

    Flow {
      width: parent.width
      visible: stream.routing
      spacing: Style.spacing.xs

      Chip {
        text: "AUTO"
        onClicked: {
          Audio.route(stream.node, null)
          stream.host.routingStreamId = -1
        }
      }

      Repeater {
        model: ScriptModel { values: Audio.lanes.concat(Audio.sinks) }
        delegate: Chip {
          required property var modelData
          text: Audio.deviceName(modelData)
          selected: stream.target === modelData
          onClicked: {
            Audio.route(stream.node, modelData)
            stream.host.routingStreamId = -1
          }
        }
      }
    }
  }

  // a loudness lane: leveler switch, fader, in/out meters and the apps it carries
  component LaneBlock: Column {
    id: lane
    required property var modelData
    property QtObject host: null
    readonly property var node: modelData
    readonly property var outNode: Audio.nodes.find(n => n.name === lane.node.name + ".out") || null
    readonly property var streams: Audio.appStreams.filter(s => Audio.sinkOf(s) === lane.node)

    // read back from the filter graph, controls named in configs/pipewire/chains.sh
    property bool levelerOn: true
    property real targetLufs: NaN

    function refresh() {
      if (!readProc.running) readProc.running = true
    }

    function levelerSet(on) {
      writeProc.command = ["pw-cli", "set-param", String(node.id), "Props",
        "{ params = [ \"amount:Mult\" " + (on ? 1 : 0) + " \"amount:Add\" " + (on ? 0 : 1) + " ] }"]
      writeProc.running = true
    }

    function parse(text) {
      var values = ({})
      try {
        var props = JSON.parse(text || "[]")[0].info.params.Props || []
        for (var i = 0; i < props.length; i++) {
          var p = props[i].params
          if (!p) continue
          for (var j = 0; j + 1 < p.length; j += 2) values[p[j]] = p[j + 1]
        }
      } catch (e) {
        return
      }
      levelerOn = values["amount:Mult"] > 0.5
      targetLufs = Number(values["target:Target LUFS"])
    }

    Process {
      id: readProc
      command: ["pw-dump", String(lane.node.id)]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: lane.parse(text)
      }
    }

    Process {
      id: writeProc
      onExited: lane.refresh()
    }

    Connections {
      target: lane.host
      function onLiveChanged() { if (lane.host.live) lane.refresh() }
    }

    Component.onCompleted: if (host && host.live) refresh()

    width: parent ? parent.width : 0
    spacing: Style.spacing.xs

    SectionHead {
      text: lane.node.description
      Chip {
        text: lane.levelerOn ? "LEVEL " + (isFinite(lane.targetLufs) ? lane.targetLufs.toFixed(0) + " LUFS" : "ON") : "LEVEL OFF"
        selected: lane.levelerOn
        onClicked: lane.levelerSet(!lane.levelerOn)
      }
    }

    Fader {
      width: parent.width
      node: lane.node
      host: lane.host
    }

    Row {
      width: parent.width
      spacing: Style.spacing.xs
      readonly property real meterWidth: (width - inLabel.width - outLabel.width - spacing * 3) / 2
      Caption { id: inLabel; text: "IN"; opacity: Style.emphasis.dim; anchors.verticalCenter: parent.verticalCenter }
      Meter { width: parent.meterWidth; anchors.verticalCenter: parent.verticalCenter; node: lane.node; active: lane.host.live }
      Caption { id: outLabel; text: "OUT"; opacity: Style.emphasis.dim; anchors.verticalCenter: parent.verticalCenter }
      Meter { width: parent.meterWidth; anchors.verticalCenter: parent.verticalCenter; node: lane.outNode; active: lane.host.live }
    }

    Repeater {
      model: ScriptModel { values: lane.streams }
      delegate: StreamRow { host: lane.host }
    }
  }

  /*
   * ---------------------------------------------------------------------------
   * PANEL
   * ---------------------------------------------------------------------------
   */

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "AUDIO"
    implicitWidth: Style.panelWidth.wide
    implicitHeight: Math.min(content.implicitHeight, maxBodyHeight) + padding * 2 + titleInset
    onShownChanged: if (!shown) root.routingStreamId = -1

    // capped to the screen, the rest scrolls
    Flickable {
      width: parent.width
      height: Math.min(content.implicitHeight, panel.maxBodyHeight)
      contentWidth: width
      contentHeight: content.implicitHeight
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.sm

        SectionHead {
          text: "OUTPUT"
          Tag {
            visible: Audio.isTappedByObs(root.sink)
            text: "OBS"
            tint: Color.semantic.live
          }
          Chip {
            text: "EQ"
            selected: Audio.eq !== null
            onClicked: Audio.eqSet(Audio.eq === null)
          }
        }

        Hero {
          value: String(Math.round(root.volume * 100))
          unit: "%"
          color: root.muted ? Color.urgent : Color.accent
        }

        Fader {
          width: content.width
          node: root.sink
          host: root
          glyph: Audio.volumeIcon(root.volume, false)
        }

        Meter {
          width: content.width
          node: root.sink
          active: root.live
        }

        Flow {
          width: content.width
          spacing: Style.spacing.xs
          Repeater {
            model: ScriptModel { values: Audio.sinks }
            delegate: Chip {
              required property var modelData
              text: Audio.deviceName(modelData)
              selected: modelData === root.sink
              onClicked: Pipewire.preferredDefaultAudioSink = modelData
            }
          }
        }

        PanelSeparator { visible: Audio.lanes.length > 0 }

        SectionHead {
          text: "LANES"
          visible: Audio.lanes.length > 0
          ButtonGroup {
            focusable: false
            fontSize: Style.font.caption
            options: root.presets.map(p => p.label)
            value: root.activePreset
            onChanged: function(v) { root.presetApply(v) }
          }
        }

        Repeater {
          model: ScriptModel { values: Audio.lanes }
          delegate: LaneBlock { host: root }
        }

        PanelSeparator {}

        PanelSectionHeader { text: "DIRECT" }

        Repeater {
          model: ScriptModel { values: Audio.appStreams.filter(s => !Audio.isLane(Audio.sinkOf(s))) }
          delegate: StreamRow { host: root }
        }

        PanelSeparator {}

        SectionHead {
          text: "MICROPHONE"
          Tag {
            visible: Audio.isTappedByObs(root.source)
            text: "OBS"
            tint: Color.semantic.live
          }
        }

        Fader {
          width: content.width
          node: root.source
          host: root
          glyph: "\u{f036c}"
          mutedGlyph: "\u{f036d}"
        }

        Meter {
          width: content.width
          node: root.source
          active: root.live
        }

        Flow {
          width: content.width
          spacing: Style.spacing.xs
          Repeater {
            model: ScriptModel { values: Audio.sources }
            delegate: Chip {
              required property var modelData
              text: Audio.deviceName(modelData)
              selected: modelData === root.source
              onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
          }
        }

        Flow {
          width: content.width
          visible: Audio.micListeners.length > 0
          spacing: Style.spacing.xs
          Caption {
            text: "HEARD BY"
            opacity: Style.emphasis.dim
            height: Style.row.control
            verticalAlignment: Text.AlignVCenter
          }
          Repeater {
            model: ScriptModel { values: Audio.micListeners }
            delegate: Tag {
              required property var modelData
              text: Audio.appName(modelData)
              tint: Audio.isObs(modelData) ? Color.semantic.live : Color.semantic.speaking
            }
          }
        }

        PanelSeparator {}

        Rectangle {
          width: content.width
          height: Style.row.list
          radius: Style.shape.data
          color: root.deafened
            ? Util.alpha(Color.urgent, 0.18)
            : (deafenHover.containsMouse ? Style.selectedFill : "transparent")

          Row {
            anchors.centerIn: parent
            spacing: Style.spacing.xs
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.deafened ? "\u{f07ce}" : "\u{f02cb}"
              color: root.deafened ? Color.urgent : Color.menu.text
              font.pixelSize: Style.font.icon
              font.family: Style.font.iconFamily
              layer.enabled: Style.fx.glow > 0 && root.deafened
              layer.effect: Glow { shadowColor: Color.urgent }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.deafened ? "Deafened, click to restore" : "Deafen (mute in + out)"
              color: root.deafened ? Color.urgent : Color.menu.text
              font.pixelSize: Style.font.body
              font.family: Style.font.family
            }
          }

          MouseArea {
            id: deafenHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleDeafen()
          }
        }
      }
    }
  }
}
