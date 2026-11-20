pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
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

  function toggleMicMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
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

      Flow {
        width: content.width
        spacing: Style.spacing.xs

        Repeater {
          model: ScriptModel {
            values: Audio.sinks
          }

          delegate: Chip {
            required property var modelData

            text: Audio.deviceName(modelData)
            selected: modelData === root.sink
            onClicked: Pipewire.preferredDefaultAudioSink = modelData
          }
        }
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

      Flow {
        width: content.width
        spacing: Style.spacing.xs

        Repeater {
          model: ScriptModel {
            values: Audio.sources
          }

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

      Row {
        width: content.width
        spacing: Style.spacing.sm

        PanelRow {
          width: (parent.width - parent.spacing) / 2
          centered: true
          enabled: root.hasMic
          glyph: root.micMuted ? "\u{f036d}" : "\u{f036c}"
          label: !root.hasMic ? "No mic" : root.micMuted ? "Mic muted" : "Mute mic"
          on: root.hasMic && root.micMuted
          onActivated: root.toggleMicMute()
        }

        PanelRow {
          width: (parent.width - parent.spacing) / 2
          centered: true
          glyph: root.deafened ? "\u{f07ce}" : "\u{f02cb}"
          label: root.deafened ? "All muted" : "Mute all"
          on: root.deafened
          onActivated: root.toggleDeafen()
        }
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

  component Meter: Item {
    id: meter
    property var node: null
    property bool active: false
    readonly property real levelDb: Audio.db(monitor.peak)

    implicitHeight: Style.spacing.xs

    PwNodePeakMonitor {
      id: monitor
      node: meter.node
      enabled: meter.active && meter.node !== null
    }

    BarGauge {
      anchors.fill: parent
      segments: 32
      value: meter.active ? Audio.meterPosition(monitor.peak) : 0
      color: Util.level(meter.levelDb, [-9, -3, -1])
    }
  }

  component NodeFader: Fader {
    id: nodeFader
    property var node: null
    readonly property bool hasAudio: !!node && !!node.audio

    volume: hasAudio ? node.audio.volume : 0
    muted: hasAudio ? node.audio.muted : false
    readoutText: Audio.levelText(volume)
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
      implicitHeight: Math.max(appIcon.height, routeChip.implicitHeight)

      IconImage {
        id: appIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: Style.font.icon + Style.spacing.sm
        source: Audio.appIcon(stream.node)
      }

      Label {
        anchors.left: appIcon.right
        anchors.leftMargin: Style.spacing.sm
        anchors.right: routeChip.left
        anchors.rightMargin: Style.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: Audio.appName(stream.node)
        color: Colors.menu.text
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

    NodeFader {
      width: parent.width
      node: Audio.levelOf(stream.node)
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
