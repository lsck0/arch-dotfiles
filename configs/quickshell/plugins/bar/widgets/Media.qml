import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Two halves:
//   - in the bar: a live cava spectrum plus play/pause and the track title
//   - on hover: album art, seek, transport, loop/shuffle, and a player picker
//
// The spectrum's audio source is Commons/Cava.qml (a ref-counted cava
// subprocess); this file holds a CavaRef only while something is actually
// looking at bars, so nothing runs when nothing is playing.
//
// All glyphs below are cmap-verified against 0xProto Nerd Font. Two near
// misses worth recording: U+F0400 is md-pi_box, not md-music_note, and the
// music-note fallback used here is fa-music U+F001.
BarWidget {
  id: root
  moduleName: "media"

  // ---- player selection -------------------------------------------------

  // dbusName of a player the user explicitly picked in the panel. Cleared
  // automatically when that player goes away, so the widget falls back to
  // the automatic choice rather than going blank.
  property string pinnedPlayer: ""

  // MPRIS can expose the same player more than once during D-Bus
  // reconnects. Keep one source per stable bus name so the picker and the
  // automatic selection do not show duplicate entries.
  readonly property var players: {
    var unique = []
    var seen = ({})
    var values = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < values.length; i++) {
      var key = String(values[i].dbusName || values[i].identity || i)
      if (seen[key] === true) continue
      seen[key] = true
      unique.push(values[i])
    }
    return unique
  }

  readonly property var player: {
    var list = players
    if (pinnedPlayer) {
      for (var i = 0; i < list.length; i++)
        if (list[i].dbusName === pinnedPlayer) return list[i]
    }
    for (var j = 0; j < list.length; j++)
      if (list[j].playbackState === MprisPlaybackState.Playing) return list[j]
    return list.length > 0 ? list[0] : null
  }

  onPlayersChanged: {
    if (!pinnedPlayer) return
    for (var i = 0; i < players.length; i++)
      if (players[i].dbusName === pinnedPlayer) return
    pinnedPlayer = ""
  }

  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player ? (player.trackAlbum || "") : ""
  readonly property bool playing: player !== null && player.playbackState === MprisPlaybackState.Playing

  // ---- spectrum ---------------------------------------------------------

  // Hold a cava reference only while bars are actually being drawn: visible,
  // available, and something is playing. The panel holds its own second
  // reference (below) so the spectrum keeps running while the panel is open
  // even if the bar widget's own conditions lapse.
  readonly property bool spectrumLive: visible && Cava.available && playing

  Loader {
    active: root.spectrumLive
    sourceComponent: CavaRef {}
  }

  visible: player !== null
  implicitWidth: row.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  function fmtTime(seconds) {
    if (!isFinite(seconds) || seconds < 0) return "0:00"
    var total = Math.floor(seconds)
    var m = Math.floor(total / 60)
    var s = total % 60
    if (m >= 60) {
      var h = Math.floor(m / 60)
      return h + ":" + String(m % 60).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }
    return m + ":" + String(s).padStart(2, "0")
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    // Six Rectangles, not Canvas/Shape/ShaderEffect. At this size the scene
    // graph batches and animates them for free; a Canvas would repaint an
    // image every frame, and a shader would mean shipping a compiled .qsb
    // for six bars.
    Row {
      id: spectrum
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.max(1, Style.spacing.xxs - 1)
      visible: root.spectrumLive
      // A longer visualizer is easier to read beside the clock/weather.
      width: Style.space(96)
      height: Math.round(root.barSize * 0.5)

      Repeater {
        model: Cava.barCount
        delegate: Rectangle {
          required property int index
          width: Math.max(2, Math.floor((spectrum.width - spectrum.spacing * (Cava.barCount - 1)) / Cava.barCount))
          radius: width / 2
          color: root.bar ? root.bar.barForeground : Color.foreground
          opacity: 0.85
          anchors.verticalCenter: parent.verticalCenter
          // Floor of 2px so the bars read as a quiet equaliser at rest
          // rather than vanishing entirely between beats.
          // Lift quiet frames so normal music produces visibly stronger motion.
          height: Math.max(2, Math.min(spectrum.height,
            spectrum.height * Math.min(100, Math.pow((Cava.values[index] || 0) / 100, 0.72) * 100) / 100))
          Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playing ? "\u{f04c}" : "\u{f04b}"
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.body

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.player) root.player.togglePlaying()
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      // Fixed, not Math.min(implicitWidth, 220). This widget now sits in the
      // centre section next to the clock, and a width that tracked the title
      // would shove the clock sideways on every track change. That jitter is
      // exactly why active-window was dropped from the bar; a little unused
      // space beats a clock that will not hold still.
      width: Style.space(200)
      elide: Text.ElideRight
      text: root.title + (root.artist ? " — " + root.artist : "")
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      opacity: 0.85
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.MiddleButton | Qt.RightButton
    onClicked: function (mouse) {
      if (!root.player) return
      if (mouse.button === Qt.MiddleButton) root.player.next()
      else if (mouse.button === Qt.RightButton) root.player.previous()
    }
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  // ---- panel ------------------------------------------------------------

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    // Centre-section widget: opens directly beneath its own trigger. See
    // Ui/HoverPanel.qml and Bar.layoutRevision for why that works now.
    anchorWidget: root
    implicitWidth: Style.space(380) + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    // Second cava reference: keeps the spectrum alive while the panel is
    // open even if playback pauses, so the panel does not visibly lose its
    // equaliser the moment you hit pause inside it.
    Loader {
      active: panel.visible && Cava.available
      sourceComponent: CavaRef {}
    }

    // MprisPlayer.position does NOT tick on its own — it is fetched on
    // demand. Emitting positionChanged() is the documented way to make the
    // binding re-read it. Only runs while the panel is open and the player
    // actually reports a position.
    Timer {
      interval: 1000
      repeat: true
      running: panel.visible && root.player !== null && root.player.positionSupported
      onTriggered: if (root.player) root.player.positionChanged()
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      // --- now playing ---
      Row {
        width: parent.width
        spacing: Style.spacing.md

        Rectangle {
          id: artFrame
          width: Style.space(72)
          height: width
          radius: Style.cornerRadius
          color: Style.selectedFillFor(Color.menu.text, Color.accent)
          clip: true

          Image {
            id: art
            anchors.fill: parent
            source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
          }

          // Not every player publishes art, and a published URL can still
          // fail to load (stale file:// path, unreachable http://). Both
          // land here rather than on an empty box.
          Text {
            anchors.centerIn: parent
            visible: !art.visible
            text: "\u{f001}"   // fa-music
            color: Color.menu.text
            opacity: 0.45
            font.family: Style.font.iconFamily
            font.pixelSize: Style.font.title
          }
        }

        Column {
          width: parent.width - artFrame.width - Style.spacing.md
          spacing: Style.spacing.xxs
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            visible: root.artist !== ""
            textFormat: Text.PlainText
            text: root.artist
            color: Color.menu.text
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            visible: root.album !== ""
            textFormat: Text.PlainText
            text: root.album
            color: Color.menu.text
            opacity: 0.45
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      // --- seek ---
      Column {
        width: parent.width
        spacing: Style.spacing.xxs
        visible: root.player !== null && root.player.lengthSupported && root.player.length > 0

        PanelSlider {
          id: seek
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: root.player && root.player.length > 0 ? root.player.length : 1
          // While dragging, the slider owns the value; otherwise it follows
          // the player. Without the guard the 1s poll above would yank the
          // knob back under the pointer mid-drag.
          value: root.player && !dragging ? root.player.position : value
          enabled: root.player !== null && root.player.canSeek
          opacity: enabled ? 1 : 0.4
          onReleased: function (v) { if (root.player && root.player.canSeek) root.player.position = v }
        }

        Row {
          width: parent.width
          Text {
            width: parent.width / 2
            text: root.player ? root.fmtTime(seek.dragging ? seek.liveValue : root.player.position) : "0:00"
            color: Color.menu.text; opacity: 0.6
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            text: root.player ? root.fmtTime(root.player.length) : "0:00"
            color: Color.menu.text; opacity: 0.6
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
        }
      }

      // --- transport ---
      Item {
        width: parent.width
        height: transport.implicitHeight

        Row {
          id: transport
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.md

          PanelActionButton {
            iconText: "\u{f074}"   // fa-shuffle
            tooltipText: "Shuffle"
            foreground: root.player && root.player.shuffle ? Color.accent : Color.menu.text
            opacity: root.player && root.player.shuffleSupported ? 1 : 0.3
            enabled: root.player !== null && root.player.shuffleSupported
            fontFamily: Style.font.family
            onClicked: if (root.player) root.player.shuffle = !root.player.shuffle
          }

          PanelActionButton {
            iconText: "\u{f048}"   // fa-step_backward
            tooltipText: "Previous"
            foreground: Color.menu.text
            opacity: root.player && root.player.canGoPrevious ? 1 : 0.3
            enabled: root.player !== null && root.player.canGoPrevious
            fontFamily: Style.font.family
            onClicked: if (root.player) root.player.previous()
          }

          PanelActionButton {
            iconText: root.playing ? "\u{f04c}" : "\u{f04b}"
            tooltipText: root.playing ? "Pause" : "Play"
            foreground: Color.menu.text
            opacity: root.player && root.player.canTogglePlaying ? 1 : 0.3
            enabled: root.player !== null && root.player.canTogglePlaying
            fontFamily: Style.font.family
            size: Style.space(30)
            onClicked: if (root.player) root.player.togglePlaying()
          }

          PanelActionButton {
            iconText: "\u{f051}"   // fa-step_forward
            tooltipText: "Next"
            foreground: Color.menu.text
            opacity: root.player && root.player.canGoNext ? 1 : 0.3
            enabled: root.player !== null && root.player.canGoNext
            fontFamily: Style.font.family
            onClicked: if (root.player) root.player.next()
          }

          PanelActionButton {
            // md-repeat / md-repeat_once — the state is carried by which
            // glyph is shown plus the accent, since there is no "repeat
            // off" glyph distinct enough to read at this size.
            iconText: root.player && root.player.loopState === MprisLoopState.Track
              ? "\u{f0458}" : "\u{f0456}"
            tooltipText: {
              if (!root.player) return "Repeat"
              switch (root.player.loopState) {
              case MprisLoopState.Track: return "Repeat: track"
              case MprisLoopState.Playlist: return "Repeat: playlist"
              default: return "Repeat: off"
              }
            }
            foreground: root.player && root.player.loopState !== MprisLoopState.None
              ? Color.accent : Color.menu.text
            opacity: root.player && root.player.loopSupported ? 1 : 0.3
            enabled: root.player !== null && root.player.loopSupported
            fontFamily: Style.font.family
            onClicked: {
              if (!root.player) return
              switch (root.player.loopState) {
              case MprisLoopState.None: root.player.loopState = MprisLoopState.Playlist; break
              case MprisLoopState.Playlist: root.player.loopState = MprisLoopState.Track; break
              default: root.player.loopState = MprisLoopState.None
              }
            }
          }
        }
      }

      // --- player picker, only when there is a choice to make ---
      Column {
        width: parent.width
        spacing: Style.spacing.xxs
        visible: root.players.length > 1

        PanelSeparator {}
        PanelSectionHeader { text: "PLAYERS" }

        Repeater {
          model: root.players
          delegate: Rectangle {
            required property var modelData
            width: content.width
            height: Style.space(28)
            radius: Style.cornerRadius
            readonly property bool current: root.player === modelData
            color: current ? Color.menu.selectedBackground : "transparent"

            // Split for the same reason as Clock.qml's reminder row: the
            // player identity is an external string, not something that
            // should be pinned to the icon font.
            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.spacing.md * 2
              spacing: Style.spacing.sm

              Text {
                textFormat: Text.PlainText
                visible: modelData.playbackState === MprisPlaybackState.Playing
                text: "\u{f04b}"
                color: parent.parent.current ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.iconFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: modelData.identity || modelData.dbusName
                color: parent.parent.current ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              // Clicking the already-pinned player unpins it, handing
              // selection back to "whatever is playing".
              onClicked: root.pinnedPlayer =
                (root.pinnedPlayer === modelData.dbusName) ? "" : modelData.dbusName
            }
          }
        }
      }
    }
  }
}
