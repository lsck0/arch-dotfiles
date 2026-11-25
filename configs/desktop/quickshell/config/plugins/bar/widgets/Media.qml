pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "media"
  barPriority: 20
  hoverPanel: true
  hoverFill: true
  panelPinOnClick: false

  readonly property var players: MediaState.players
  readonly property var player: MediaState.player

  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? MediaState.tag(player.trackArtist) : ""
  readonly property string album: player ? MediaState.tag(player.trackAlbum) : ""
  readonly property bool playing: player !== null && player.playbackState === MprisPlaybackState.Playing
  // a player without a title (a tab with no media metadata, an idle player) names itself, as the panel does
  readonly property string line: (title || (player ? String(player.identity || "") : "")) + (artist ? " :: " + artist : "")

  readonly property string artUrl: MediaState.artUrl

  readonly property var playerStreams: {
    var entry = String(player ? (player.desktopEntry || "") : "").toLowerCase()
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : [] // qmllint disable missing-property
    var out = []
    if (!entry) return out
    for (let i = 0; i < nodes.length; i++) {
      let n = nodes[i]
      if (n && n.isStream && n.isSink && String(n.name || "").toLowerCase() === entry) out.push(n)
    }
    return out
  }
  readonly property var volumeStream: playerStreams.length > 0 ? playerStreams[0] : null
  readonly property bool mprisVolume: player !== null && player.volumeSupported && player.canControl
    && String(player.dbusName).indexOf("plasma-browser-integration") === -1
  readonly property bool volumeAvailable: mprisVolume || volumeStream !== null
  readonly property real playerVolume: mprisVolume ? player.volume
    : volumeStream && volumeStream.audio ? volumeStream.audio.volume : 0
  readonly property bool playerMuted: mprisVolume ? player.volume === 0
    : volumeStream && volumeStream.audio ? volumeStream.audio.muted : false
  property real unmuteVolume: 1

  function setPlayerVolume(v) {
    if (mprisVolume) {
      player.volume = v
      return
    }
    for (let i = 0; i < playerStreams.length; i++) {
      let audio = playerStreams[i].audio
      if (!audio) continue
      audio.volume = v
      if (v > 0) audio.muted = false
    }
  }

  function togglePlayerMute() {
    if (mprisVolume) {
      if (player.volume > 0) {
        unmuteVolume = player.volume
        player.volume = 0
      } else {
        player.volume = unmuteVolume
      }
      return
    }
    var muted = !playerMuted
    for (let i = 0; i < playerStreams.length; i++)
      if (playerStreams[i].audio) playerStreams[i].audio.muted = muted
  }

  PwObjectTracker { objects: root.playerStreams }

  // any player playing keeps the widget up, so a paused player pinned while another plays stays shown
  readonly property bool active: playing || players.some(p => p.playbackState === MprisPlaybackState.Playing)

  // set, not bound: a binding on active would drop to false for the one evaluation before the linger starts, hiding
  // the widget and closing its panel on every pause
  property bool recentlyActive: false
  onActiveChanged: if (active) recentlyActive = true; else lingerTimer.restart()

  Timer {
    id: lingerTimer
    interval: 30000
    onTriggered: root.recentlyActive = root.active
  }

  Component.onCompleted: {
    recentlyActive = active
    Cava.source = spectrumSource
  }

  // bar_spectrum in mod.nu, unless this widget's own setting says otherwise
  readonly property bool barSpectrum: setting("barSpectrum", Prefs.barSpectrum) === true
  readonly property bool spectrumLive: barSpectrum && visible && Cava.available && playing
    && !(root.bar && root.bar.quiet)

  // cava captures devices and sink monitors, not a stream: the player's loopback sink (desktop/pipewire), else all output
  readonly property var spectrumSink: volumeStream ? Audio.targetsOf(volumeStream).find(t => Audio.isLoopbackSink(t)) : null
  readonly property string spectrumSource: spectrumSink ? spectrumSink.name + ".monitor" : ""
  onSpectrumSourceChanged: Cava.source = spectrumSource

  Loader {
    active: root.spectrumLive
    sourceComponent: CavaRef {}
  }

  visible: player !== null && recentlyActive
  implicitWidth: row.implicitWidth + Style.bar.itemPaddingX * 2

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    // the cells exist only while they show: hidden ones would still re-evaluate on every cava frame
    Loader {
      anchors.verticalCenter: parent.verticalCenter
      active: root.spectrumLive
      visible: active
      sourceComponent: CavaBars {
        rows: 4
        targetWidth: Style.space(96)
        targetHeight: Style.bar.sizeHorizontal * 0.4
      }
    }

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: root.playing ? "\u{f04c}" : "\u{f04b}"
      color: Colors.bar.text
      icon: true
    }

    Label {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(200)
      elide: Text.ElideRight
      text: (MediaState.pinnedPlayer !== "" && root.player && root.player.dbusName === MediaState.pinnedPlayer
        ? "\u{f0403} " : "") + root.line
      dim: true
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: function (mouse) {
      if (!root.player) return
      if (mouse.button === Qt.LeftButton) root.player.togglePlaying()
      else if (mouse.button === Qt.MiddleButton) root.player.next()
      else if (mouse.button === Qt.RightButton) root.player.previous()
    }
  }

  // the position the seek bar and clock read, only while the panel shows: MPRIS sends no updates while a track runs, so
  // it is sampled each frame while the player plays, and set once on opening and on every jump, pause, track or player
  // change
  property real position: 0
  readonly property real length: player && player.lengthSupported && player.length > 0 ? player.length : 0

  function syncPosition() {
    if (!panel.visible) return
    position = player && player.positionSupported ? Math.max(0, player.position) : 0
  }

  onPlayerChanged: syncPosition()
  onPlayingChanged: syncPosition()

  Connections {
    target: root.player
    function onPositionChanged() { root.syncPosition() }
    function onPostTrackChanged() { root.syncPosition() }
  }

  // a change that moves the track's text and art in, the panel's own opening has its boot-in
  readonly property string trackKey: player ? player.dbusName + "\n" + title + "\n" + artist : ""
  onTrackKeyChanged: if (panel.visible) trackIn.restart()

  HoverPanel {
    id: panel
    anchorWidget: root
    title: "MEDIA"
    accent: MediaState.accent
    accentText: MediaState.accentText
    implicitWidth: Style.panelWidth.normal

    onVisibleChanged: if (visible) root.syncPosition()

    Loader {
      active: panel.visible && Cava.available
      sourceComponent: CavaRef {}
    }

    // a sample only when the bar would move half a pixel or the clock a second, so the fill glides without a rebind
    // every frame
    FrameAnimation {
      running: panel.visible && root.playing && root.player.positionSupported && !seek.dragging
      onTriggered: {
        var p = root.player.position
        var px = root.length > 0 ? Math.abs(p - root.position) * seek.width / root.length : 0
        if (px >= 0.5 || Math.floor(p) !== Math.floor(root.position)) root.position = p
      }
    }

    ParallelAnimation {
      id: trackIn
      NumberAnimation {
        target: trackRow; property: "opacity"; from: 0.25; to: 1
        duration: Style.motion.base; easing.type: Style.motion.fastEasing
      }
      NumberAnimation {
        target: trackShift; property: "x"; from: Style.motion.travel; to: 0
        duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter
      }
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      Flow {
        width: parent.width
        spacing: Style.spacing.xs
        visible: root.players.length > 1

        Repeater {
          model: root.players
          delegate: Button {
            required property var modelData
            required property int index
            readonly property string name: String(modelData.identity || modelData.dbusName)
            // two players of one app (two mpv) are told apart by their place among their namesakes
            readonly property int namesake: root.players.slice(0, index)
              .filter(p => String(p.identity || p.dbusName) === name).length
            variant: "chip"
            focusable: true
            iconText: modelData.playbackState === MprisPlaybackState.Playing ? "\u{f04b}" : "\u{f04c}"
            text: namesake > 0 ? name + " " + (namesake + 1) : name
            selected: root.player === modelData
            onClicked: MediaState.pinnedPlayer = MediaState.pinnedPlayer === modelData.dbusName ? "" : modelData.dbusName
          }
        }
      }

      Row {
        id: trackRow
        width: parent.width
        spacing: Style.spacing.md
        transform: Translate { id: trackShift }

        Rectangle {
          id: artFrame
          width: Style.space(80)
          height: width
          radius: Style.shape.surface
          color: Style.selectedFillFor(Colors.menu.text, MediaState.accent)
          clip: true

          Label {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "\u{f001}"
            dim: true
            icon: true
            font.pixelSize: Style.font.heading
          }

          Image {
            id: art
            anchors.fill: parent
            source: MediaState.artSource
            // twice the frame: a 16:9 video thumbnail is cropped to the square, and decoded at the frame's width its
            // height would fall short and be scaled up, soft beside a square album cover
            sourceSize.width: Math.ceil(artFrame.width * 2 * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.motion.base; easing.type: Style.motion.fastEasing } }
            onStatusChanged: if (status === Image.Error) MediaState.artFailed()
          }

          HudFrame { color: MediaState.accent }
        }

        Column {
          width: parent.width - artFrame.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Label {
            width: parent.width
            text: root.title || (root.player ? root.player.identity : "")
            color: Colors.menu.text
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            layer.enabled: Style.fx.glow > 0
            layer.effect: Glow {}
          }
          Label {
            width: parent.width
            text: root.artist
            visible: text !== ""
            color: Colors.menu.text
            elide: Text.ElideRight
          }
          Label {
            width: parent.width
            text: root.album
            visible: text !== ""
            dim: true
            caption: true
            elide: Text.ElideRight
          }
        }
      }

      Loader {
        anchors.horizontalCenter: parent.horizontalCenter
        active: panel.visible && Cava.available
        visible: active
        sourceComponent: CavaBars {
          rows: 8
          targetWidth: content.width
          targetHeight: Style.space(48)
        }
      }

      Column {
        width: parent.width
        spacing: 0
        visible: root.length > 0

        Slider {
          id: seek
          width: parent.width
          step: 5
          maximum: Math.max(1, root.length)
          value: Math.min(root.position, maximum)
          enabled: root.player !== null && root.player.canSeek
          opacity: enabled ? 1 : Style.emphasis.disabled
          fillColor: MediaState.accent
          onReleased: function (v) {
            if (!root.player || !root.player.canSeek) return
            root.player.position = v
            root.position = v
          }
        }

        Item {
          width: parent.width
          height: elapsed.implicitHeight

          Label {
            id: elapsed
            anchors.left: parent.left
            text: Util.clock(seek.dragging ? seek.liveValue : root.position)
            dim: true
            caption: true
            font.features: { "tnum": 1 }
          }
          Label {
            anchors.right: parent.right
            text: Util.clock(root.length)
            dim: true
            caption: true
            font.features: { "tnum": 1 }
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacing.sm

        TransportButton {
          iconText: "\u{f074}"
          tooltipText: root.player && root.player.shuffle ? "Shuffle: on" : "Shuffle: off"
          foreground: root.player && root.player.shuffle ? MediaState.accentText : Colors.menu.text
          visible: root.player !== null && root.player.shuffleSupported
          onClicked: if (root.player) root.player.shuffle = !root.player.shuffle
        }

        TransportButton {
          iconText: "\u{f048}"
          tooltipText: "Previous"
          enabled: root.player !== null && root.player.canGoPrevious
          onClicked: if (root.player) root.player.previous()
        }

        TransportButton {
          iconText: root.playing ? "\u{f04c}" : "\u{f04b}"
          tooltipText: root.playing ? "Pause" : "Play"
          enabled: root.player !== null && root.player.canTogglePlaying
          fontSize: Style.font.icon + Style.space(4)
          onClicked: if (root.player) root.player.togglePlaying()
        }

        TransportButton {
          iconText: "\u{f051}"
          tooltipText: "Next"
          enabled: root.player !== null && root.player.canGoNext
          onClicked: if (root.player) root.player.next()
        }

        TransportButton {
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
            ? MediaState.accentText : Colors.menu.text
          visible: root.player !== null && root.player.loopSupported
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

      Fader {
        width: parent.width
        visible: root.player !== null
        enabled: root.volumeAvailable
        value: root.playerVolume
        muted: root.playerMuted
        glyph: Audio.volumeIcon(root.playerVolume, false)
        mutedGlyph: Audio.volumeIcon(root.playerVolume, true)
        readoutText: root.volumeAvailable ? Math.round(root.playerVolume * 100) + "%" : "--"
        onMoved: function (v) { root.setPlayerVolume(v) }
        onMuteToggled: root.togglePlayerMute()
      }
    }
  }

  component TransportButton: Button {
    focusable: true
    variant: "icon"
    foreground: Colors.menu.text
    fontFamily: Style.font.family
  }

  component CavaBars: Row {
    id: spec
    property int rows: 4
    property real targetWidth: 0
    property real targetHeight: 0
    readonly property int cellHeight: Math.max(2, Math.floor((targetHeight - (rows - 1)) / rows))
    readonly property int cellWidth: Math.max(2, Math.floor((targetWidth - spacing * (Cava.barCount - 1)) / Cava.barCount))
    // BarGauge's segments: one accent (the cover's while it plays), unlit cells a faint track, the head lighter; the
    // held peak in accent2
    readonly property color litColor: MediaState.accent
    readonly property color headColor: Qt.lighter(litColor, 1.35)
    readonly property color capColor: Colors.accent2

    function heightFrac(level) { return Math.min(1, Math.pow(Math.max(0, Math.min(1, level / 100)), 0.5) * 1.4) }

    spacing: Math.max(1, Style.spacing.xxs - 1)
    width: cellWidth * Cava.barCount + spacing * (Cava.barCount - 1)
    height: cellHeight * rows + rows - 1

    Repeater {
      model: Cava.barCount
      delegate: Column {
        id: sbar
        required property int index
        readonly property int lit: Math.round(spec.heightFrac(Cava.values[sbar.index] || 0) * spec.rows)
        readonly property int cap: Math.ceil(spec.heightFrac(Cava.peaks[sbar.index] || 0) * spec.rows)
        spacing: 1
        width: spec.cellWidth

        Repeater {
          model: spec.rows
          delegate: Rectangle {
            id: cell
            required property int index
            readonly property int n: spec.rows - cell.index
            width: sbar.width
            height: spec.cellHeight
            antialiasing: false
            color: cell.n > sbar.lit ? (sbar.cap === cell.n && sbar.cap > sbar.lit ? spec.capColor : Util.alpha(spec.litColor, 0.13))
              : cell.n === sbar.lit ? spec.headColor : spec.litColor
          }
        }
      }
    }
  }
}
