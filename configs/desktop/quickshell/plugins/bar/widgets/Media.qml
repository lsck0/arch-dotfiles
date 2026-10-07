import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "media"

  // dbusName picked in the panel
  property string pinnedPlayer: ""

  function duplicateScore(p) {
    return (p.playbackState === MprisPlaybackState.Playing ? 8 : 0)
      + (p.trackArtUrl ? 4 : 0) + (p.lengthSupported && p.length > 0 ? 2 : 0) + (p.trackTitle ? 1 : 0)
  }

  // mpris can duplicate players during d-bus reconnects
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
        // prefer playing, then the copy with art
        if (duplicateScore(p) > duplicateScore(byIdentity[idKey])) byIdentity[idKey] = p
      }
    }
    var deduped = []
    for (var k = 0; k < order.length; k++) deduped.push(byIdentity[order[k]])
    return deduped
  }

  property string lastShownPlayer: ""

  // assigned, not bound
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

  // players does not change on playback with a single player
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

  // youtube thumbnail fallback from the video id
  readonly property string artUrl: {
    if (!player) return ""
    if (player.trackArtUrl) return player.trackArtUrl
    var url = String((player.metadata && player.metadata["xesam:url"]) || "")
    var m = url.match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/)|youtu\.be\/)([\w-]{11})/)
    return m ? "https://i.ytimg.com/vi/" + m[1] + "/mqdefault.jpg" : ""
  }

  // qt in-process tls crashes, so remote art is fetched by curl
  readonly property bool artRemote: /^https?:\/\//i.test(root.artUrl)
  // tmpfs, so remote covers never outlive the session; no runtime dir means no remote art
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string artCacheDir: runtimeDir ? runtimeDir + "/quickshell-mediaart" : ""
  readonly property string artCacheFile:
    root.artRemote && root.artCacheDir ? (root.artCacheDir + "/" + Qt.md5(root.artUrl)) : ""
  readonly property int artCacheKeep: 50
  // a remote fetch tells the art host what is playing: only at home with no vpn, tor or anonymous socks up;
  // anywhere else the cache is dropped and only file:// art shows
  readonly property string artFetchCheck: "[ -e /run/home-network ]"
    + " && ! ip link show proton0 >/dev/null 2>&1 && ! ip link show wg0 >/dev/null 2>&1"
    + " && ! systemctl -q is-active tor-router.service && ! systemctl --user -q is-active anonymous-socks-tor.service"

  property string artSource: ""
  property string artFetchedUrl: ""
  // retry budget per url
  property int artTries: 0

  function fetchArt() {
    artProc.running = false
    if (!root.artCacheFile) return
    root.artFetchedUrl = root.artUrl
    artProc.running = true
  }

  function refreshArt() {
    root.artTries = 0
    root.artSource = ""
    var u = root.artUrl
    if (!u) { artProc.running = false; return }
    if (!root.artRemote) { artProc.running = false; root.artSource = u; return }
    fetchArt()
  }

  onArtUrlChanged: refreshArt()

  Process {
    id: artDropProc
    command: ["rm", "-f", "--", root.artCacheFile]
    onExited: root.fetchArt()
  }

  // the cached file is reused only while the check still passes
  Process {
    id: artProc
    command: ["sh", "-c",
      "d=$1 f=$2; if ! { " + root.artFetchCheck + "; }; then rm -rf -- \"$d\"; exit 1; fi; " +
      "[ -s \"$f\" ] && exit 0; mkdir -p -m 700 -- \"$d\" || exit 1; " +
      "curl -sfL --max-time 8 -o \"$f.part\" \"$3\" && mv -f -- \"$f.part\" \"$f\" || { rm -f -- \"$f.part\"; exit 1; }; " +
      "ls -1t -- \"$d\" | tail -n +" + (root.artCacheKeep + 1) + " | while IFS= read -r o; do rm -f -- \"$d/$o\"; done",
      "sh", root.artCacheDir, root.artCacheFile, root.artUrl]
    onExited: function (exitCode) {
      if (exitCode !== 0) return
      if (root.artFetchedUrl !== root.artUrl) return
      // force a reload of the unchanged source
      root.artSource = ""
      root.artSource = "file://" + root.artCacheFile
    }
  }

  // prefer mpris volume, spotify resets stream volume per track
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
  // plasma-browser-integration always reports 0
  readonly property bool mprisVolume: player !== null && player.volumeSupported && player.canControl
    && String(player.dbusName).indexOf("plasma-browser-integration") === -1
  readonly property bool volumeAvailable: mprisVolume || volumeStream !== null
  readonly property real playerVolume: mprisVolume ? player.volume
    : volumeStream && volumeStream.audio ? volumeStream.audio.volume : 0
  readonly property bool playerMuted: mprisVolume ? player.volume === 0
    : volumeStream && volumeStream.audio ? volumeStream.audio.muted : false
  // mpris has no mute, restored on unmute
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

  // stays visible for a while after playback stops
  readonly property bool recentlyActive: playing || lingerTimer.running
  onPlayingChanged: if (!playing) lingerTimer.restart()

  Timer {
    id: lingerTimer
    interval: 30000
  }

  Component.onCompleted: {
    updatePlayer()
    Cava.source = spectrumSource
    refreshArt()
  }

  // the bar spectrum is opt-in (widget setting barSpectrum): it repaints the bar at cava's framerate
  readonly property bool barSpectrum: setting("barSpectrum", false) === true
  readonly property bool spectrumLive: barSpectrum && visible && Cava.available && playing
    && !(root.bar && root.bar.quiet)

  // this player's stream, not the whole sink
  readonly property string spectrumSource: volumeStream ? String(volumeStream.name || "") : ""
  onSpectrumSourceChanged: Cava.source = spectrumSource

  Loader {
    active: root.spectrumLive
    sourceComponent: CavaRef {}
  }

  visible: player !== null && recentlyActive
  implicitWidth: row.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  function specColor(frac, valMul, a) {
    var c = Color.accent
    var h = (c.hsvHue < 0 ? 0 : c.hsvHue) + (frac - 0.5) * 0.16
    if (h < 0) h += 1
    else if (h > 1) h -= 1
    return Qt.hsva(h, c.hsvSaturation, Math.min(1, c.hsvValue * valMul), a)
  }

  // sqrt lifts quiet passages, gain makes peaks pop; shared by bars and peak caps
  function specHeightFrac(level) { return Math.min(1, Math.pow(level, 0.5) * 1.4) }

  Rectangle {
    anchors.fill: parent
    radius: Style.shape.data
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Row {
      id: spectrum
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.max(1, Style.spacing.xxs - 1)
      visible: root.spectrumLive
      width: Style.space(96)
      height: Math.round(root.barSize * 0.5)

      Repeater {
        model: Cava.barCount
        delegate: Item {
          id: sbar
          required property int index
          readonly property real level: Math.min(1, (Cava.values && Cava.values[index] || 0) / 100)
          readonly property real peak: Math.min(1, (Cava.peaks && Cava.peaks[index] || 0) / 100)
          readonly property real frac: Cava.barCount > 1 ? index / (Cava.barCount - 1) : 0
          width: Math.max(2, Math.floor((spectrum.width - spectrum.spacing * (Cava.barCount - 1)) / Cava.barCount))
          height: spectrum.height

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            radius: 0
            antialiasing: false
            opacity: 0.4 + sbar.level * 0.6
            // center stop brightens with intensity so loud bars glow hotter
            gradient: Gradient {
              GradientStop { position: 0.0; color: root.specColor(sbar.frac, 1.0, 0.2) }
              GradientStop { position: 0.5; color: root.specColor(sbar.frac, 1.1 + sbar.level, 1.0) }
              GradientStop { position: 1.0; color: root.specColor(sbar.frac, 1.0, 0.2) }
            }
            height: Math.max(2, spectrum.height * root.specHeightFrac(sbar.level))
          }

          // peak caps ride the held maximum, mirrored like the center-out bar
          Rectangle {
            width: parent.width; height: 1
            color: root.specColor(sbar.frac, 1.6, 0.9)
            y: parent.height / 2 - parent.height / 2 * root.specHeightFrac(sbar.peak) - height
          }
          Rectangle {
            width: parent.width; height: 1
            color: root.specColor(sbar.frac, 1.6, 0.9)
            y: parent.height / 2 + parent.height / 2 * root.specHeightFrac(sbar.peak)
          }
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
        // above hoverArea, which only pauses
        z: 1
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.player) root.player.togglePlaying()
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(200)
      elide: Text.ElideRight
      text: root.title + (root.artist ? " :: " + root.artist : "")
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
      // left click only pauses, never resumes
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

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "MEDIA"
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    // keeps the spectrum alive while paused with the panel open
    Loader {
      active: panel.visible && Cava.available
      sourceComponent: CavaRef {}
    }

    // position does not tick on its own
    Timer {
      interval: 1000
      repeat: true
      running: panel.visible && root.player !== null && root.player.positionSupported
      onTriggered: if (root.player) root.player.positionChanged()
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Rectangle {
          id: artFrame
          width: Style.space(72)
          height: width
          radius: Style.shape.surface
          color: Style.selectedFillFor(Color.menu.text, Color.accent)
          clip: true

          Image {
            id: art
            anchors.fill: parent
            source: root.artSource
            sourceSize.width: Math.ceil(artFrame.width * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            onStatusChanged: {
              // a truncated cache file: drop it and fetch once more
              if (status === Image.Error && root.artRemote && root.artTries < 2) {
                root.artTries += 1
                root.artSource = ""
                artDropProc.running = true
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !art.visible
            text: "\u{f001}"   // fa-music
            color: Color.menu.text
            opacity: Style.emphasis.faint
            font.family: Style.font.iconFamily
            font.pixelSize: Style.font.title
          }

          HudFrame {}
        }

        Column {
          width: parent.width - artFrame.width - Style.spacing.sm
          spacing: Style.spacing.xxs
          anchors.verticalCenter: parent.verticalCenter

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            layer.enabled: Style.fx.glow > 0
            layer.effect: Glow {}
          }
          Text {
            width: parent.width
            // opacity, not visible, so the popup does not jump
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

      Item {
        id: panelSpectrum
        width: parent.width
        height: Style.space(72)
        // redrawn at cava's frame rate, so no glow
        visible: panel.visible && Cava.available

        Row {
          id: panelBars
          anchors.fill: parent
          spacing: Math.max(1, Style.spacing.xxs - 1)

          Repeater {
            model: Cava.barCount
            delegate: Item {
              id: pbar
              required property int index
              readonly property real level: Math.min(1, (Cava.values && Cava.values[index] || 0) / 100)
              readonly property real peak: Math.min(1, (Cava.peaks && Cava.peaks[index] || 0) / 100)
              readonly property real frac: Cava.barCount > 1 ? index / (Cava.barCount - 1) : 0
              width: Math.max(2, Math.floor((panelBars.width - panelBars.spacing * (Cava.barCount - 1)) / Cava.barCount))
              height: panelSpectrum.height

              Rectangle {
                anchors.centerIn: parent
                width: parent.width
                radius: 0
                antialiasing: false
                height: Math.max(2, parent.height * Math.pow(pbar.level, 0.6))
                opacity: 0.45 + pbar.level * 0.55
                gradient: Gradient {
                  GradientStop { position: 0.0; color: root.specColor(pbar.frac, 1.0, 0.16) }
                  GradientStop { position: 0.5; color: root.specColor(pbar.frac, 1.1 + pbar.level, 1.0) }
                  GradientStop { position: 1.0; color: root.specColor(pbar.frac, 1.0, 0.16) }
                }
                Behavior on height { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
              }

              Rectangle {
                width: parent.width
                height: Math.max(1, Style.spacing.xxs - 1)
                color: root.specColor(pbar.frac, 1.6, 0.9)
                y: pbar.height / 2 - pbar.height / 2 * Math.pow(pbar.peak, 0.6) - height
                Behavior on y { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
              }
              Rectangle {
                width: parent.width
                height: Math.max(1, Style.spacing.xxs - 1)
                color: root.specColor(pbar.frac, 1.6, 0.9)
                y: pbar.height / 2 + pbar.height / 2 * Math.pow(pbar.peak, 0.6)
                Behavior on y { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
              }
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.xxs
        // opacity, not visible, so the popup does not jump
        readonly property bool supported:
          root.player !== null && root.player.lengthSupported && root.player.length > 0
        opacity: supported ? 1 : 0

        Slider {
          id: seek
          width: parent.width
          bar: root.bar
          minimum: 0
          maximum: root.player && root.player.length > 0 ? root.player.length : 1
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
            text: root.player ? Util.clock(seek.dragging ? seek.liveValue : root.player.position) : "0:00"
            color: Color.menu.text; opacity: 0.6
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            text: root.player ? Util.clock(root.player.length) : "0:00"
            color: Color.menu.text; opacity: 0.6
            font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
        }
      }

      Item {
        width: parent.width
        height: transport.implicitHeight

        Row {
          id: transport
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.sm

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
            // bigger glyph, not button, row top-aligns children
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
            // md-repeat / md-repeat_once
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

      Row {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.player !== null
        opacity: root.volumeAvailable ? 1 : 0.4

        Item {
          width: Style.space(24)
          height: playerVolumeSlider.height
          Text {
            anchors.centerIn: parent
            text: Audio.volumeIcon(root.playerVolume, root.playerMuted)
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

        Slider {
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
          text: root.volumeAvailable ? Math.round(root.playerVolume * 100) + "%" : "--"
          color: Color.menu.text
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      BarGauge {
        width: content.width
        height: Style.spacing.sm
        segments: 24
        visible: root.player !== null
        opacity: root.volumeAvailable ? 1 : 0.4
        value: root.playerVolume
        color: root.playerMuted ? Color.urgent : Color.accent
      }

      Column {
        width: parent.width
        spacing: Style.spacing.xxs
        visible: root.players.length > 1

        PanelSeparator {}
        PanelSectionHeader { text: "PLAYERS" }

        Repeater {
          model: root.players
          delegate: PanelRow {
            required property var modelData
            width: content.width
            on: root.player === modelData
            glyph: modelData.playbackState === MprisPlaybackState.Playing ? "\u{f04b}" : ""
            label: modelData.identity || modelData.dbusName
            // clicking the pinned player unpins it
            onActivated: root.pinnedPlayer =
              (root.pinnedPlayer === modelData.dbusName) ? "" : modelData.dbusName
          }
        }
      }
    }
  }
}
