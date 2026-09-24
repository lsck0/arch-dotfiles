import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell.
BarWidget {
  id: root
  moduleName: "media"

  // ---- player selection -------------------------------------------------

  // dbusName of a player the user explicitly picked in the panel.
  property string pinnedPlayer: ""

  function duplicateScore(p) {
    return (p.playbackState === MprisPlaybackState.Playing ? 8 : 0)
      + (p.trackArtUrl ? 4 : 0) + (p.lengthSupported && p.length > 0 ? 2 : 0) + (p.trackTitle ? 1 : 0)
  }

  // MPRIS can expose the same player more than once during D-Bus reconnects.
  readonly property var players: {
    var unique = []
    var seen = ({})
    var values = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < values.length; i++) {
      var bus = String(values[i].dbusName || "")
      if (bus.indexOf("playerctld") !== -1) continue
      var key = bus || String(values[i].identity || i)
      if (seen[key] === true) continue
      seen[key] = true
      unique.push(values[i])
    }

    var byIdentity = ({})
    var order = []
    for (var j = 0; j < unique.length; j++) {
      var p = unique[j]
      var idKey = String(p.identity || p.dbusName).toLowerCase().trim()
      if (byIdentity[idKey] === undefined) {
        byIdentity[idKey] = p
        order.push(idKey)
      } else {
        // Playing beats paused, then art beats none: Firefox's own service publishes no artwork, plasma-browser-integration does.
        if (duplicateScore(p) > duplicateScore(byIdentity[idKey])) byIdentity[idKey] = p
      }
    }
    var deduped = []
    for (var k = 0; k < order.length; k++) deduped.push(byIdentity[order[k]])
    return deduped
  }

  property string lastShownPlayer: ""

  // WHICH PLAYER THE WIDGET IS SHOWING — assigned, not bound.
  property var player: null

  function pickPlayer() {
    var list = players
    if (pinnedPlayer) {
      for (var i = 0; i < list.length; i++)
        if (list[i].dbusName === pinnedPlayer) return list[i]
    }
    for (var j = 0; j < list.length; j++)
      if (list[j].playbackState === MprisPlaybackState.Playing) return list[j]
    if (lastShownPlayer) {
      for (var k = 0; k < list.length; k++)
        if (list[k].dbusName === lastShownPlayer) return list[k]
    }
    return list.length > 0 ? list[0] : null
  }

  function updatePlayer() {
    var next = pickPlayer()
    if (next !== player) player = next
    lastShownPlayer = player ? player.dbusName : ""
  }

  // `players` only reads playbackState while collapsing DUPLICATE identities, so with a single player nothing in that binding depends on playback at all and playersChanged never fires when it starts or stops.
  readonly property string playbackKey: {
    var values = Mpris.players ? Mpris.players.values : []
    var key = ""
    for (var i = 0; i < values.length; i++)
      key += values[i].dbusName + ":" + values[i].playbackState + ";"
    return key
  }

  onPlaybackKeyChanged: updatePlayer()
  onPinnedPlayerChanged: updatePlayer()

  onPlayersChanged: {
    if (pinnedPlayer) {
      var stillThere = false
      for (var i = 0; i < players.length; i++)
        if (players[i].dbusName === pinnedPlayer) stillThere = true
      if (!stillThere) pinnedPlayer = ""
    }
    updatePlayer()
  }

  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player ? (player.trackAlbum || "") : ""
  readonly property bool playing: player !== null && player.playbackState === MprisPlaybackState.Playing

  // YouTube does not always hand the browser artwork (then neither Firefox nor plasma-browser-integration publishes any), but the thumbnail URL follows from the video id.
  readonly property string artUrl: {
    if (!player) return ""
    if (player.trackArtUrl) return player.trackArtUrl
    var url = String((player.metadata && player.metadata["xesam:url"]) || "")
    var m = url.match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/)|youtu\.be\/)([\w-]{11})/)
    return m ? "https://i.ytimg.com/vi/" + m[1] + "/mqdefault.jpg" : ""
  }

  // Players with MPRIS Volume are driven through it: Spotify re-applies its own volume to the stream on every track change, undoing a PipeWire-level change.
  readonly property var playerStreams: {
    var entry = String(player ? (player.desktopEntry || "") : "").toLowerCase()
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    var out = []
    if (!entry) return out
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && n.isSink && String(n.name || "").toLowerCase() === entry) out.push(n)
    }
    return out
  }
  readonly property var volumeStream: playerStreams.length > 0 ? playerStreams[0] : null
  // plasma-browser-integration reports a constant 0 while audio plays; it gets the stream.
  readonly property bool mprisVolume: player !== null && player.volumeSupported && player.canControl
    && String(player.dbusName).indexOf("plasma-browser-integration") === -1
  readonly property bool volumeAvailable: mprisVolume || volumeStream !== null
  readonly property real playerVolume: mprisVolume ? player.volume
    : volumeStream && volumeStream.audio ? volumeStream.audio.volume : 0
  readonly property bool playerMuted: mprisVolume ? player.volume === 0
    : volumeStream && volumeStream.audio ? volumeStream.audio.muted : false
  // MPRIS has no mute, so muting there is volume 0 and this is what comes back.
  property real unmuteVolume: 1

  function setPlayerVolume(v) {
    if (mprisVolume) {
      player.volume = v
      return
    }
    for (var i = 0; i < playerStreams.length; i++) {
      var audio = playerStreams[i].audio
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
    for (var i = 0; i < playerStreams.length; i++)
      if (playerStreams[i].audio) playerStreams[i].audio.muted = muted
  }

  PwObjectTracker { objects: root.playerStreams }

  // ---- auto-hide after silence ------------------------------------------

  property real lastPlayingAt: 0
  property real nowMs: Date.now()
  readonly property bool recentlyActive:
    playing || (lastPlayingAt > 0 && (nowMs - lastPlayingAt) < 30000)

  onPlayingChanged: if (playing) lastPlayingAt = Date.now()
  Component.onCompleted: {
    updatePlayer()
    if (playing) lastPlayingAt = Date.now()
    Cava.source = spectrumSource
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.player !== null && !root.playing && root.lastPlayingAt > 0
    onTriggered: root.nowMs = Date.now()
  }

  // ---- spectrum ---------------------------------------------------------

  // Hold a cava reference only while bars are actually being drawn: visible, available, and something is playing.
  readonly property bool spectrumLive: visible && Cava.available && playing

  // Point cava at THIS player's PipeWire stream rather than the speakers, so a Discord call in the same sink does not drive the bars.
  readonly property string spectrumSource: volumeStream ? String(volumeStream.name || "") : ""
  onSpectrumSourceChanged: Cava.source = spectrumSource

  Loader {
    active: root.spectrumLive
    sourceComponent: CavaRef {}
  }

  visible: player !== null && recentlyActive
  implicitWidth: row.implicitWidth + Style.bar.itemPaddingX * 2
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

    // Six Rectangles, not Canvas/Shape/ShaderEffect.
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
          readonly property real level: Math.min(1, (Cava.values[index] || 0) / 100)
          width: Math.max(2, Math.floor((spectrum.width - spectrum.spacing * (Cava.barCount - 1)) / Cava.barCount))
          radius: width / 2
          // Bars tint toward the accent colour as they get louder — reads as a warmer, more "alive" equaliser than a flat single-colour one, and costs nothing extra since it's still a plain Rectangle fill.
          color: Qt.tint(root.bar ? root.bar.barForeground : Color.foreground,
            Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, level * 0.55))
          opacity: 0.85 + level * 0.15
          anchors.verticalCenter: parent.verticalCenter
          // Floor of 2px so the bars read as a quiet equaliser at rest rather than vanishing entirely between beats.
          height: Math.max(2, Math.min(spectrum.height,
            spectrum.height * Math.min(100, Math.pow(level, 0.5) * 1.2 * 100) / 100))
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
        // z above hoverArea: this glyph stays a dedicated toggle (play AND pause) even though the wider hoverArea below now treats a plain click anywhere else on the widget as "pause only" (see hoverArea's onClicked).
        z: 1
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.player) root.player.togglePlaying()
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      // Fixed, not Math.min(implicitWidth, 220).
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
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: function (mouse) {
      if (!root.player) return
      // Left click anywhere on the tray widget (outside the dedicated play/pause glyph, which keeps its own toggle above via z: 1) pauses — a quick "shut it up" gesture that doesn't also risk resuming something you meant to silence.
      if (mouse.button === Qt.LeftButton) {
        if (root.player.canPause) root.player.pause()
        else root.player.togglePlaying()
      }
      else if (mouse.button === Qt.MiddleButton) root.player.next()
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
    // Centre-section widget: opens directly beneath its own trigger.
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    // Second cava reference: keeps the spectrum alive while the panel is open even if playback pauses, so the panel does not visibly lose its equaliser the moment you hit pause inside it.
    Loader {
      active: panel.visible && Cava.available
      sourceComponent: CavaRef {}
    }

    // MprisPlayer.position does NOT tick on its own — it is fetched on demand.
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
            source: root.artUrl
            // Album art arrives at whatever size the player publishes — often 1000x1000 or larger — and is drawn in a 72px box.
            sourceSize.width: Math.ceil(artFrame.width * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
          }

          // Not every player publishes art, and a published URL can still fail to load (stale file:// path, unreachable http://).
          Text {
            anchors.centerIn: parent
            visible: !art.visible
            text: "\u{f001}"   // fa-music
            color: Color.menu.text
            opacity: Style.emphasis.faint
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
            // Always in the layout (never visible: false) even with no artist tag: a Column positioner drops the space of a hidden child entirely, and this line popping in/out was one of the two big contributors to the popup "jumping" between tracks and players.
            textFormat: Text.PlainText
            text: root.artist
            color: Color.menu.text
            opacity: root.artist !== "" ? Style.emphasis.dim : 0
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            // Same reasoning as the artist line above.
            textFormat: Text.PlainText
            text: root.album
            color: Color.menu.text
            opacity: root.album !== "" ? Style.emphasis.faint : 0
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
        // Always laid out, even for a player that doesn't report a length — hiding this whole block used to remove/restore ~40px the instant the active player changed to (or from) one without seek support, which was the other big source of the popup "jumping" (see the artist/album Text above for the same fix applied to metadata). The slider and labels just read as a disabled 0:00 track instead.
        readonly property bool supported:
          root.player !== null && root.player.lengthSupported && root.player.length > 0
        opacity: supported ? 1 : 0

        PanelSlider {
          id: seek
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: root.player && root.player.length > 0 ? root.player.length : 1
          // While dragging, the slider owns the value; otherwise it follows the player.
          value: root.player && !dragging ? root.player.position : value
          enabled: root.player !== null && root.player.canSeek
          opacity: enabled ? 1 : 0.4
          onReleased: function (v) {
            if (!root.player || !root.player.canSeek) return
            root.player.position = v
            root.player.positionChanged()
          }
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
            // A bigger glyph, not a bigger button: Row (a positioner) does not vertically centre children of differing implicitHeight — it top-aligns them — so a taller button here threw the whole transport row out of line.
            fontSize: Style.font.icon + Style.space(4)
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
            // md-repeat / md-repeat_once — the state is carried by which glyph is shown plus the accent, since there is no "repeat off" glyph distinct enough to read at this size.
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

      // --- volume, same row shape as the audio panel's output slider ---
      Row {
        width: parent.width
        spacing: Style.spacing.md
        visible: root.player !== null
        opacity: root.volumeAvailable ? 1 : 0.4

        Item {
          width: Style.space(24)
          height: playerVolumeSlider.height
          Text {
            anchors.centerIn: parent
            // md-volume_off / high / medium / low
            text: root.playerMuted ? "\u{f0581}" : root.playerVolume > 0.66 ? "\u{f057e}"
              : root.playerVolume > 0 ? "\u{f0580}" : "\u{f057f}"
            color: root.playerMuted ? Color.urgent : Color.menu.text
            font.pixelSize: Style.font.icon
            font.family: Style.font.iconFamily
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.volumeAvailable
            cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePlayerMute()
          }
        }

        PanelSlider {
          id: playerVolumeSlider
          width: content.width - Style.space(24) - Style.space(40) - parent.spacing * 2
          bar: root.bar
          enabled: root.volumeAvailable
          value: root.playerVolume
          onMoved: function(v) { root.setPlayerVolume(v) }
          onRightClicked: root.togglePlayerMute()
        }

        Text {
          width: Style.space(40)
          height: playerVolumeSlider.height
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          text: root.volumeAvailable ? Math.round(root.playerVolume * 100) + "%" : "–"
          color: Color.menu.text
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
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
          // The player identity is an external string and stays on the UI family; only the play glyph comes from the icon font, which is what PanelRow's own glyph/label split already does.
          delegate: PanelRow {
            required property var modelData
            width: content.width
            on: root.player === modelData
            glyph: modelData.playbackState === MprisPlaybackState.Playing ? "\u{f04b}" : ""
            label: modelData.identity || modelData.dbusName
            // Clicking the already-pinned player unpins it, handing selection back to "whatever is playing".
            onActivated: root.pinnedPlayer =
              (root.pinnedPlayer === modelData.dbusName) ? "" : modelData.dbusName
          }
        }
      }
    }
  }
}
