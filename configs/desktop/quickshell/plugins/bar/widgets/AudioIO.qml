pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool hasMic: !!source && !!source.audio
  readonly property bool micMuted: hasMic ? source.audio.muted : true
  readonly property bool live: panel.shown
  property int routingStreamId: -1
  readonly property bool deafened: muted && micMuted
  function toggleMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  function toggleDeafen() {
    var target = !deafened
    if (sink && sink.audio) sink.audio.muted = target
    if (source && source.audio) source.audio.muted = target
  }

  moduleName: "audio-io"
  barPriority: 70

  hoverPanel: true
  hoverFill: true
  visible: sink !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker {
    objects: [root.sink, root.source].filter(n => !!n)
      .concat(root.live ? Audio.appStreams.concat(Audio.loopbackOuts, Audio.micListeners, Audio.sinks) : [])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Audio.volumeIcon(root.volume, root.muted)
    tooltipText: (root.muted ? "Muted" : Audio.levelText(root.volume)) + " :: MMB mute"
    onPressed: function(b) { if (b === Qt.MiddleButton) root.toggleMute() }
    onWheelMoved: function(delta) { Audio.nudge(root.sink, delta) }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    title: "AUDIO"
    implicitWidth: Style.panelWidth.wide
    onShownChanged: if (!shown) root.routingStreamId = -1

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      PanelSectionHeader { text: "OUTPUT" }

      NodeFader {
        width: content.width
        node: root.sink
        glyph: Audio.volumeIcon(root.volume, false)
      }

      Item {
        width: content.width
        visible: ObsProcess.connected || ObsProcess.listening
        implicitHeight: hearGroup.implicitHeight

        Caption {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "HEAR"
          color: Colors.textDim
        }

        ButtonGroup {
          id: hearGroup
          anchors.right: parent.right
          spacing: Style.spacing.xs
          options: [{ value: "me", label: "SYSTEM" }, { value: "obs", label: "OBS OUTPUT" }]
          value: ObsProcess.listening ? "obs" : "me"
          onChanged: function(v) { ObsProcess.listenSet(v === "obs") }
        }
      }

      DeviceGroup {
        width: content.width
        nodes: Audio.sinks
        current: root.sink
        onPicked: function(node) { Pipewire.preferredDefaultAudioSink = node }
      }

      PanelSeparator {}

      PanelSectionHeader { text: "MICROPHONE" }

      Label {
        visible: !root.hasMic
        text: "> NO MICROPHONE"
        dim: true
        caption: true
      }

      NodeFader {
        visible: root.hasMic
        width: content.width
        node: root.source
        glyph: "\u{f036c}"
        mutedGlyph: "\u{f036d}"
      }

      Meter {
        visible: root.hasMic
        width: content.width
        node: root.source
        active: root.live
      }

      DeviceGroup {
        width: content.width
        nodes: Audio.sources
        current: root.source
        onPicked: function(node) { Pipewire.preferredDefaultAudioSource = node }
      }

      Flow {
        width: content.width
        visible: Audio.micListeners.length > 0
        spacing: Style.spacing.xs

        Caption {
          text: "HEARD BY"
          color: Colors.textDim
        }

        Repeater {
          model: ScriptModel {
            values: Audio.micListeners
          }

          delegate: Tag {
            required property var modelData

            text: Audio.appName(modelData)
            tint: Audio.isObs(modelData) ? Colors.semantic.live : Colors.semantic.speaking
          }
        }
      }

      Column {
        width: content.width
        spacing: Style.spacing.sm
        visible: Audio.appStreams.length > 0

        PanelSeparator {}

        PanelSectionHeader { text: "APPS" }

        Repeater {
          model: ScriptModel {
            values: Audio.appStreams
          }

          delegate: StreamRow {
            host: root
          }
        }
      }

      PanelSeparator {}

      PanelRow {
        width: content.width
        centered: true
        glyph: root.deafened ? "\u{f07ce}" : "\u{f02cb}"
        label: root.deafened ? "All muted" : "Mute all"
        on: root.deafened
        onActivated: root.toggleDeafen()
      }

      PanelSeparator {}

      PanelRow {
        width: parent.width
        glyph: "\u{f1049}"
        label: "Patchbay (qpwgraph)"
        onActivated: {
          root.closePanel()
          Quickshell.execDetached(["uwsm-app", "--", "qpwgraph"])
        }
      }
    }
  }

  component Chip: Button {
    variant: "chip"
    focusable: true
  }

  component Caption: Label {
    color: Colors.menu.text
    elide: Text.ElideRight
    caption: true
  }

  component Tag: Rectangle {
    id: tag
    property string text: ""
    property color tint: Colors.accent

    implicitWidth: tagLabel.implicitWidth + Style.spacing.sm * 2
    implicitHeight: tagLabel.implicitHeight + Style.spacing.xxs * 2
    radius: Style.shape.data
    color: Util.alpha(tint, Style.tintFillAlpha)
    border.color: Util.alpha(tint, 0.6)
    border.width: Style.spacing.hair

    Label {
      id: tagLabel
      anchors.centerIn: parent
      text: tag.text
      color: Colors.textOnFill(tag.tint, tag.color)
      caption: true
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.labelTracking
    }
  }

  // the level rises at once and falls at fallRate; the peak holds for holdMs, then falls the same way
  component Meter: Item {
    id: meter
    property var node: null
    property bool active: false
    readonly property real levelDb: Audio.db(monitor.peak)
    readonly property real level: active ? Audio.meterPosition(monitor.peak) : 0
    readonly property real fallRate: 1.5
    readonly property int holdMs: 800
    property real shown: 0
    property real held: 0

    implicitHeight: Style.spacing.xs

    onLevelChanged: {
      if (level >= shown) {
        shownFall.stop()
        shown = level
      } else {
        shownFall.to = level
        shownFall.restart()
      }
      if (level >= held) {
        heldFall.stop()
        held = level
        holdTimer.restart()
      }
    }

    SmoothedAnimation { id: shownFall; target: meter; property: "shown"; velocity: meter.fallRate }
    SmoothedAnimation { id: heldFall; target: meter; property: "held"; to: 0; velocity: meter.fallRate }

    Timer {
      id: holdTimer
      interval: meter.holdMs
      onTriggered: heldFall.restart()
    }

    PwNodePeakMonitor {
      id: monitor
      node: meter.node
      enabled: meter.active && meter.node !== null
    }

    BarGauge {
      anchors.fill: parent
      segments: 32
      animated: false
      value: meter.shown
      hold: meter.held
      color: Util.level(meter.levelDb, [-9, -3, -1])
    }
  }

  component DeviceGroup: ButtonGroup {
    id: group
    property var nodes: []
    property var current: null

    signal picked(var node)

    spacing: Style.spacing.xs
    options: nodes.map(n => ({ value: String(n.id), label: Audio.deviceName(n) }))
    value: current ? String(current.id) : ""
    onChanged: function(v) {
      const node = group.nodes.find(n => String(n.id) === v)
      if (node && node !== group.current) group.picked(node)
    }
  }

  component NodeFader: Fader {
    id: nodeFader
    property var node: null
    readonly property bool hasAudio: !!node && !!node.audio

    value: hasAudio ? node.audio.volume : 0
    muted: hasAudio ? node.audio.muted : false
    readoutText: Audio.levelText(value)
    readoutWidest: "100% +00.0 dB"
    onMoved: function(v) { if (nodeFader.hasAudio) nodeFader.node.audio.volume = v }
    onMuteToggled: if (nodeFader.hasAudio) nodeFader.node.audio.muted = !nodeFader.node.audio.muted
  }

  component StreamRow: Column {
    id: stream
    required property var modelData
    property AudioIO host: null
    readonly property var node: modelData
    readonly property var target: Audio.sinkOf(node)
    readonly property bool routing: host !== null && host.routingStreamId === node.id

    width: parent ? parent.width : 0
    spacing: Style.spacing.xs

    Item {
      width: parent.width
      implicitHeight: Math.max(streamFader.implicitHeight, routeButton.height)

      NodeFader {
        id: streamFader
        anchors.left: parent.left
        anchors.right: routeButton.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        node: Audio.levelOf(stream.node)
        caption: Audio.appName(stream.node)
        captionWidth: Style.space(96)
        iconSource: Audio.appIcon(stream.node)
      }

      Button {
        id: routeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        variant: "icon"
        focusable: true
        size: streamFader.glyphSize
        iconText: "\u{f0a1e}"
        selected: stream.routing
        foreground: stream.routing ? Colors.accentText : Colors.menu.text
        tooltipText: "> " + Audio.deviceName(stream.target)
        onClicked: stream.host.routingStreamId = stream.routing ? -1 : stream.node.id
      }
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
        model: ScriptModel {
          values: Audio.sinks
        }

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
}
