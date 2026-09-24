import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell.
BarWidget {
  id: root
  moduleName: "audio-io"

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0

  readonly property var source: Pipewire.defaultAudioSource
  readonly property bool micMuted: source && source.audio ? source.audio.muted : true
  readonly property real micVolume: source && source.audio ? source.audio.volume : 0

  property var sinks: []
  property var sources: []
  property string defaultSinkName: ""
  property string defaultSourceName: ""

  PwObjectTracker { objects: (root.sink ? [root.sink] : []).concat(root.source ? [root.source] : []) }

  visible: sink !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function iconFor() {
    if (muted) return "󰝟"
    if (volume > 0.66) return "󰕾"
    if (volume > 0) return "󰖀"
    return "󰕿"
  }

  function toggleMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  function toggleMicMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  // "Deafened" is both ends muted at once — the state a call app means by the word.
  readonly property bool deafened: muted && micMuted

  // Undeafening restores both to unmuted rather than to whatever they were before.
  function toggleDeafen() {
    var target = !deafened
    if (sink && sink.audio) sink.audio.muted = target
    if (source && source.audio) source.audio.muted = target
  }

  function refreshDevices() {
    if (!devicesProc.running) devicesProc.running = true
  }

  // Re-read after pactl has had a moment to apply.
  Timer {
    id: devicesSettle
    interval: 250
    onTriggered: root.refreshDevices()
  }

  function setSink(name) {
    Quickshell.execDetached(["pactl", "set-default-sink", name])
    devicesSettle.restart()
  }

  function setSource(name) {
    Quickshell.execDetached(["pactl", "set-default-source", name])
    devicesSettle.restart()
  }

  Process {
    id: devicesProc
    command: [Paths.barWidget("audio-devices.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          root.sinks = d.sinks || []
          root.sources = d.sources || []
          root.defaultSinkName = d.defaultSink || ""
          root.defaultSourceName = d.defaultSource || ""
        } catch (e) {}
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconFor()
    tooltipText: root.muted ? "Muted" : Math.round(root.volume * 100) + "%"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleMute()
    }
    onWheelMoved: function(delta) {
      if (!root.sink || !root.sink.audio) return
      var step = 0.05
      root.sink.audio.volume = Math.max(0, Math.min(1, root.volume + (delta > 0 ? step : -step)))
    }
    onEntered: root.bar.hoverOpen(root.moduleName)
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    onOpened: root.refreshDevices()
    implicitWidth: Style.panelWidth.narrow + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader { text: "OUTPUT" }

      Row {
        width: content.width
        spacing: Style.spacing.md

        Item {
          width: Style.space(24)
          height: volumeSlider.height
          Text {
            anchors.centerIn: parent
            text: root.iconFor()
            color: root.muted ? Color.urgent : Color.menu.text
            font.pixelSize: Style.font.icon
            font.family: Style.font.iconFamily
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMute()
          }
        }

        PanelSlider {
          id: volumeSlider
          width: content.width - Style.space(24) - Style.space(40) - parent.spacing * 2
          bar: root.bar
          value: root.volume
          onMoved: function(v) { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
          onRightClicked: root.toggleMute()
        }

        Text {
          width: Style.space(40)
          height: volumeSlider.height
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          text: Math.round(root.volume * 100) + "%"
          color: Color.menu.text
          opacity: Style.emphasis.dim
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      Repeater {
        model: root.sinks
        // Shared Ui/PanelRow — the ●/○ prefix used to be concatenated into the label string, so the gap after it was whatever the font gave it rather than the row spacing every other list uses.
        PanelRow {
          required property var modelData
          width: content.width
          stateMarker: true
          on: modelData.name === root.defaultSinkName
          label: modelData.description
          onActivated: root.setSink(modelData.name)
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "MICROPHONE" }

      Row {
        width: content.width
        spacing: Style.spacing.md

        Item {
          width: Style.space(24)
          height: micSlider.height
          Text {
            anchors.centerIn: parent
            text: root.micMuted ? "󰍭" : "󰍬"
            color: root.micMuted ? Color.urgent : Color.menu.text
            font.pixelSize: Style.font.icon
            font.family: Style.font.iconFamily
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMicMute()
          }
        }

        PanelSlider {
          id: micSlider
          width: content.width - Style.space(24) - Style.space(40) - parent.spacing * 2
          bar: root.bar
          value: root.micVolume
          onMoved: function(v) { if (root.source && root.source.audio) root.source.audio.volume = v }
          onRightClicked: root.toggleMicMute()
        }

        Text {
          width: Style.space(40)
          height: micSlider.height
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          text: Math.round(root.micVolume * 100) + "%"
          color: Color.menu.text
          opacity: Style.emphasis.dim
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      // Input devices, directly under the microphone slider they belong to.
      Repeater {
        model: root.sources
        PanelRow {
          required property var modelData
          width: content.width
          stateMarker: true
          on: modelData.name === root.defaultSourceName
          label: modelData.description
          onActivated: root.setSource(modelData.name)
        }
      }

      PanelSeparator {}

      // Deafen spans both sections, so it goes last rather than inside either.
      Rectangle {
        width: content.width
        height: Style.row.list
        radius: Style.cornerRadius
        color: root.deafened
          ? Util.alpha(Color.urgent, 0.18)
          : (deafenHover.containsMouse ? Style.selectedFill : "transparent")

        Row {
          anchors.centerIn: parent
          spacing: Style.spacing.sm
          Text {
            anchors.verticalCenter: parent.verticalCenter
            // md-headphones_off / md-headphones, both cmap-verified.
            text: root.deafened ? "\u{f07ce}" : "\u{f02cb}"
            color: root.deafened ? Color.urgent : Color.menu.text
            font.pixelSize: Style.font.icon
            font.family: Style.font.iconFamily
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.deafened ? "Deafened — click to restore" : "Deafen (mute in + out)"
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
