pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "Palette.js" as Palette

// The player the bar shows, its cover art fetched once for every screen, the accent taken from that art while it plays,
// and the `media` IPC target the media keys drive, so keys, bar and agents act on the same player.
//
// The shown player: the pinned one; else the playing one that started last; else, with all paused, the one shown
// before; else the one that played last. A pin holds until its player vanishes or another starts playing.
Singleton {
  id: root

  property string pinnedPlayer: ""

  readonly property string browserIntegrationBus: "plasma-browser-integration"

  function duplicateScore(p) {
    // playing outweighs all metadata
    return (p.playbackState === MprisPlaybackState.Playing ? 16 : 0) + (p.trackArtUrl ? 4 : 0)
      + (p.trackArtist ? 4 : 0) + (p.lengthSupported && p.length > 0 ? 2 : 0) + (p.trackTitle ? 1 : 0)
  }

  // a browser tab without media metadata reports its site's address as the album or artist: no tag then
  function tag(v) { return /^[a-z]+:\/\//i.test(String(v || "")) ? "" : String(v || "") }

  function isBrowserIntegration(p) {
    return String(p.dbusName || "").indexOf(browserIntegrationBus) !== -1
  }

  // OBS's own browser sources and an app's idle media session (a closed tab, a chat client's webview: no title, not
  // playing) are not media to show
  function isNoise(p) {
    var name = String(p.identity || "") + " " + String(p.desktopEntry || "")
    if (/\bobs\b|obsproject/i.test(name)) return true
    return !p.trackTitle && p.playbackState !== MprisPlaybackState.Playing
  }

  // playerctld only proxies the others
  function isIgnored(p) { return String(p.dbusName || "").indexOf("playerctld") !== -1 || isNoise(p) }

  // one player per bus, a browser tab and its plasma-browser-integration twin folded by identity into the richer one
  readonly property var players: {
    var values = Mpris.players ? Mpris.players.values : [] // qmllint disable missing-property
    var seen = ({})
    var kept = []
    for (let i = 0; i < values.length; i++) {
      let p = values[i]
      let bus = String(p.dbusName || "")
      let key = bus || String(p.identity || i)
      if (seen[key] || isIgnored(p)) continue
      seen[key] = true
      let identity = String(p.identity || "").toLowerCase().trim()
      let twin = identity ? kept.findIndex(held => String(held.identity || "").toLowerCase().trim() === identity
        && (isBrowserIntegration(p) || isBrowserIntegration(held))) : -1
      if (twin === -1) kept.push(p)
      else if (duplicateScore(p) > duplicateScore(kept[twin])) kept[twin] = p
    }
    return kept
  }

  property string lastShownPlayer: ""

  property var player: null

  // bus -> order in which it last started playing, and the buses playing at the last look; plain maps, read only here
  property var startedAt: ({})
  property var wasPlaying: ({})
  property int startCount: 0

  function startOf(p) { return root.startedAt[p.dbusName] || 0 }
  function latest(list) { return list.reduce((best, p) => !best || startOf(p) > startOf(best) ? p : best, null) }

  function pickPlayer() {
    var byBus = name => name ? players.find(p => p.dbusName === name) : undefined
    return byBus(pinnedPlayer) || latest(players.filter(p => p.playbackState === MprisPlaybackState.Playing))
      || byBus(lastShownPlayer) || latest(players.filter(p => startOf(p) > 0)) || players[0] || null
  }

  function updatePlayer() {
    var next = pickPlayer()
    if (next !== player) player = next
    lastShownPlayer = player ? player.dbusName : ""
  }

  // stamps each player that went to playing since the last look, forgets the vanished, and drops a pin another
  // player's start overrides
  function notePlayback() {
    var values = Mpris.players ? Mpris.players.values : [] // qmllint disable missing-property
    var now = ({})
    var started = []
    for (let i = 0; i < values.length; i++) {
      let p = values[i]
      if (p.playbackState !== MprisPlaybackState.Playing || isIgnored(p)) continue
      now[p.dbusName] = true
      if (!root.wasPlaying[p.dbusName]) started.push(p.dbusName)
    }
    var stamps = ({})
    for (let i = 0; i < values.length; i++) {
      let bus = values[i].dbusName
      if (root.startedAt[bus]) stamps[bus] = root.startedAt[bus]
    }
    for (let i = 0; i < started.length; i++) stamps[started[i]] = ++root.startCount
    root.startedAt = stamps
    root.wasPlaying = now
    if (pinnedPlayer && started.some(bus => bus !== pinnedPlayer)) pinnedPlayer = ""
  }

  readonly property string playbackKey: Array.from(Mpris.players ? Mpris.players.values : []) // qmllint disable missing-property
    .map(p => p.dbusName + ":" + p.playbackState).join(";")

  onPlaybackKeyChanged: {
    notePlayback()
    updatePlayer()
  }
  onPinnedPlayerChanged: updatePlayer()

  onPlayersChanged: {
    notePlayback()
    if (pinnedPlayer && !players.some(p => p.dbusName === pinnedPlayer)) pinnedPlayer = ""
    updatePlayer()
  }

  Component.onCompleted: {
    notePlayback()
    updatePlayer()
    refreshArt()
  }

  readonly property bool playing: player !== null && player.playbackState === MprisPlaybackState.Playing

  readonly property string artUrl: {
    if (!player) return ""
    // only a remote image or a local file: some players report a bare directory (file:///, file://) for no cover
    var art = String(player.trackArtUrl || "")
    if (/^https?:\/\/./i.test(art) || /^file:\/\/\/.*[^\/]$/.test(art)) return art
    var url = String((player.metadata && player.metadata["xesam:url"]) || "")
    var m = url.match(/(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/)|youtu\.be\/)([\w-]{11})/)
    return m ? "https://i.ytimg.com/vi/" + m[1] + "/mqdefault.jpg" : ""
  }

  readonly property bool artRemote: /^https?:\/\//i.test(root.artUrl)
  readonly property string artCacheDir: Paths.runtimeDir + "/quickshell-mediaart"
  readonly property string artCacheFile:
    root.artRemote ? (root.artCacheDir + "/" + Qt.md5(root.artUrl)) : ""
  readonly property int artCacheKeep: 50
  readonly property string artFetchCheck: "[ -e /run/trusted-network ]"
    + " && ! ip link show proton0 >/dev/null 2>&1 && ! ip link show wg0 >/dev/null 2>&1"
    + " && ! systemctl -q is-active tor-router.service && ! systemctl --user -q is-active anonymous-socks-tor.service"
  readonly property int artTriesMax: 2

  // a local file url the art Image loads, empty while a remote cover is fetched or when there is none
  property string artSource: ""
  property string artFetchedUrl: ""
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
    // a player with no art may still send "file:///", a directory, which only floods the log with load errors
    if (!u || u.endsWith("/")) { artProc.running = false; return }
    if (!root.artRemote) { artProc.running = false; root.artSource = u; return }
    fetchArt()
  }

  // a cached cover that fails to decode is dropped and fetched again, a bounded number of times
  function artFailed() {
    if (!root.artRemote || root.artTries >= root.artTriesMax) return
    root.artTries += 1
    root.artSource = ""
    artDropProc.running = true
  }

  onArtUrlChanged: refreshArt()

  Process {
    id: artDropProc
    command: ["rm", "-f", "--", root.artCacheFile]
    onExited: root.fetchArt()
  }

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
      root.artSource = ""
      root.artSource = "file://" + root.artCacheFile
    }
  }

  // the cover's own colour (scripts/art-accent.nu, once per image content), "" when it has none or none is known yet
  property string artPicked: ""
  readonly property string artPath: root.artSource.startsWith("file://") ? root.pathFromUrl(root.artSource) : ""
  // the file the running or last pick was for: a pick runs to its end, then the next starts if the art moved on
  property string artPickedPath: ""

  function pathFromUrl(url) {
    try { return decodeURIComponent(url.slice("file://".length)) } catch (e) { return url.slice("file://".length) }
  }

  function pickAccent() {
    if (accentProc.running || !root.artPath || root.artPickedPath === root.artPath) return
    root.artPickedPath = root.artPath
    accentProc.running = true
  }

  onArtPathChanged: {
    root.artPicked = ""
    root.artPickedPath = ""
    pickAccent()
  }

  Process {
    id: accentProc
    command: [Paths.script("art-accent.nu"), root.artPickedPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.artPickedPath === root.artPath) root.artPicked = text.trim()
    }
    onExited: root.pickAccent()
  }

  // the picked colour held at the theme accent's stroke contrast and, for text, at Colors.textFor's; null while
  // nothing plays or the art gives no colour, so a media surface binds `MediaState.artAccent ?? Colors.accent`
  readonly property var artAccent: {
    if (!root.playing || !root.artPicked) return null
    var bg = Colors.background
    var out = Palette.readableOn([bg.r, bg.g, bg.b], Palette.hexToRgb(root.artPicked), Theme.values.accentContrast)
    return Qt.rgba(out[0], out[1], out[2], 1)
  }
  readonly property var artAccentText: root.playing && root.artPicked ? Colors.textFor(Qt.color(root.artPicked)) : null

  // what the Media widget, its panel and its spectrum draw with: the art's accent, else the theme's
  property color accent: root.artAccent ?? Colors.accent
  property color accentText: root.artAccentText ?? Colors.accentText
  Behavior on accent { ColorAnimation { duration: Style.motion.base; easing.type: Style.motion.fastEasing } }
  Behavior on accentText { ColorAnimation { duration: Style.motion.base; easing.type: Style.motion.fastEasing } }

  // each returns {icon, title} as json for the OSD, empty when no player can take the action, so the caller falls back
  function act(can: string, icon: string, action: var): string {
    var p = root.player
    if (!p || !p[can]) return ""
    var title = p.trackTitle || p.identity || ""
    action(p)
    return JSON.stringify({ icon: icon, title: title })
  }

  IpcHandler {
    target: "media"

    function playPause(): string {
      return root.act("canTogglePlaying", root.playing ? "media-pause" : "media-play", p => p.togglePlaying())
    }
    function next(): string { return root.act("canGoNext", "media-next", p => p.next()) }
    function previous(): string { return root.act("canGoPrevious", "media-previous", p => p.previous()) }
    function stop(): string { return root.act("canControl", "media-stop", p => p.stop()) }
  }
}
