import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Volume readout uses Quickshell's own
// Pipewire binding (already proven in Microphone.qml); device switching
// shells out to pactl since Quickshell's Pipewire binding doesn't expose a
// "set default sink/source" call, only live volume/mute state.
//
// Merged with the microphone: output mute/volume, output devices, input
// (mic) mute/volume, and input devices all live in this one panel now —
// Microphone.qml keeps its own bar icon (mute shortcut + wheel-scroll), but
// hovering it opens this same panel (moduleName "audio-io") rather than
// duplicating the device/volume UI in a second panel.
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

  // "Deafened" is both ends muted at once — the state a call app means by
  // the word. Derived rather than stored, so it stays correct when either
  // side is muted individually or from outside the shell (a headset button,
  // a keybind, another app).
  readonly property bool deafened: muted && micMuted

  // Undeafening restores both to unmuted rather than to whatever they were
  // before. Remembering prior state sounds friendlier but is a trap: mute
  // can change from outside the shell while deafened, and restoring a stale
  // snapshot would then silently re-mute a device the user had just
  // unmuted.
  function toggleDeafen() {
    var target = !deafened
    if (sink && sink.audio) sink.audio.muted = target
    if (source && source.audio) source.audio.muted = target
  }

  function refreshDevices() {
    if (!devicesProc.running) devicesProc.running = true
  }

  function setSink(name) {
    Quickshell.execDetached(["pactl", "set-default-sink", name])
    refreshDevices()
  }

  function setSource(name) {
    Quickshell.execDetached(["pactl", "set-default-source", name])
    refreshDevices()
  }

  Process {
    id: devicesProc
    command: [Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets/audio-devices.sh"]
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
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refreshDevices() }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.space(320) + Style.shadowOffset
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
          opacity: 0.6
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      Repeater {
        model: root.sinks
        Rectangle {
          required property var modelData
          width: content.width
          height: Style.space(32)
          radius: Style.cornerRadius
          color: modelData.name === root.defaultSinkName ? Color.menu.selectedBackground : "transparent"
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: (modelData.name === root.defaultSinkName ? "● " : "○ ") + modelData.description
            color: modelData.name === root.defaultSinkName ? Color.menu.selectedText : Color.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            elide: Text.ElideRight
            width: parent.width - Style.spacing.md * 2
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setSink(modelData.name)
          }
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
          opacity: 0.6
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      PanelSeparator {}

      Rectangle {
        width: content.width
        height: Style.space(32)
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

      Repeater {
        model: root.sources
        Rectangle {
          required property var modelData
          width: content.width
          height: Style.space(32)
          radius: Style.cornerRadius
          color: modelData.name === root.defaultSourceName ? Color.menu.selectedBackground : "transparent"
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: (modelData.name === root.defaultSourceName ? "● " : "○ ") + modelData.description
            color: modelData.name === root.defaultSourceName ? Color.menu.selectedText : Color.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            elide: Text.ElideRight
            width: parent.width - Style.spacing.md * 2
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setSource(modelData.name)
          }
        }
      }
    }
  }
}
