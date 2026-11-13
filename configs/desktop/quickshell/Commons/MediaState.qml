pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// The player the bar shows (the pinned one, else a playing one, else the last shown) and the `media` IPC target the
// media keys drive, so keys, bar and agents act on the same player.
Singleton {
  id: root

  property string pinnedPlayer: ""

  function duplicateScore(p) {
    return (p.playbackState === MprisPlaybackState.Playing ? 8 : 0)
      + (p.trackArtUrl ? 4 : 0) + (p.lengthSupported && p.length > 0 ? 2 : 0) + (p.trackTitle ? 1 : 0)
  }

  // one player per bus, then per identity (a browser's tabs), the richest one kept; playerctld only proxies the others
  readonly property var players: {
    var values = Mpris.players ? Mpris.players.values : [] // qmllint disable missing-property
    var seen = ({})
    var byIdentity = ({})
    for (let i = 0; i < values.length; i++) {
      let p = values[i]
      let bus = String(p.dbusName || "")
      let key = bus || String(p.identity || i)
      if (bus.indexOf("playerctld") !== -1 || seen[key]) continue
      seen[key] = true
      let idKey = String(p.identity || p.dbusName).toLowerCase().trim()
      let held = byIdentity[idKey]
      if (!held || duplicateScore(p) > duplicateScore(held)) byIdentity[idKey] = p
    }
    return Object.values(byIdentity)
  }

  property string lastShownPlayer: ""

  property var player: null

  function pickPlayer() {
    var byBus = name => name ? players.find(p => p.dbusName === name) : undefined
    return byBus(pinnedPlayer) || players.find(p => p.playbackState === MprisPlaybackState.Playing)
      || byBus(lastShownPlayer) || players[0] || null
  }

  function updatePlayer() {
    var next = pickPlayer()
    if (next !== player) player = next
    lastShownPlayer = player ? player.dbusName : ""
  }

  readonly property string playbackKey: Array.from(Mpris.players ? Mpris.players.values : []) // qmllint disable missing-property
    .map(p => p.dbusName + ":" + p.playbackState).join(";")

  onPlaybackKeyChanged: updatePlayer()
  onPinnedPlayerChanged: updatePlayer()

  onPlayersChanged: {
    if (pinnedPlayer && !players.some(p => p.dbusName === pinnedPlayer)) pinnedPlayer = ""
    updatePlayer()
  }

  Component.onCompleted: updatePlayer()

  // each returns {icon, title} as json for the OSD, empty when no player can take the action, so the caller falls back
  function act(can: bool, icon: string, action: var): string {
    if (!root.player || !can) return ""
    var title = root.player.trackTitle || root.player.identity || ""
    action()
    return JSON.stringify({ icon: icon, title: title })
  }

  IpcHandler {
    target: "media"

    function playPause(): string {
      var p = root.player
      var icon = p && p.playbackState === MprisPlaybackState.Playing ? "media-pause" : "media-play"
      return root.act(p !== null && p.canTogglePlaying, icon, () => p.togglePlaying())
    }
    function next(): string { return root.act(root.player !== null && root.player.canGoNext, "media-next", () => root.player.next()) }
    function previous(): string {
      return root.act(root.player !== null && root.player.canGoPrevious, "media-previous", () => root.player.previous())
    }
    function stop(): string { return root.act(root.player !== null && root.player.canControl, "media-stop", () => root.player.stop()) }
  }
}
