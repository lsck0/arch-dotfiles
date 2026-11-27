#!/usr/bin/env -S nu --no-config-file
# The media path end to end: fake MPRIS players on a private session bus drive a copy of the shell (MediaState, the
# bar's Media widget, the lock's media line) under an offscreen quickshell, and each scenario checks what the bar and
# the lock show, and the accent the media surfaces take from a generated cover. The copy stubs the PanelWindow hover
# panel, shortens the pause linger and never fetches art.

const SHELL = path self ../../..
const DRIVER = r#'
# run by media.test.nu inside a private session bus and runtime dir: driver.py <shell tree> <work dir>

import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

LINGER_MS = 1000
# Colors.qml's accent with no colors.json, and a cover colour readable as is on its background
THEME_ACCENT = "#39bae6"
ART_ORANGE = "#FF8000"
# an upper bound on reaching a state, never a wait: generous for a loaded machine, and a pass costs no more
SETTLE_S = 20.0
MPRIS = "org.mpris.MediaPlayer2"
PLAYER = MPRIS + ".Player"
PROPS = "org.freedesktop.DBus.Properties"
OBJ = "/org/mpris/MediaPlayer2"
# MprisPlaybackState as the shell prints it
STATUS = {"Stopped": 0, "Playing": 1, "Paused": 2}

HOVER_STUB = """import QtQuick
// test stand-in: the real one is a PanelWindow, which has no backend offscreen
Item {
  property var anchorWidget: null
  property string title: ""
  property color accent
  property color accentText
  default property alias body: inner.data
  visible: false
  Item { id: inner }
}
"""

SHELL = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import "plugins/bar/widgets"

ShellRoot {
  id: shell
  Item {
    Media { id: media }
    LockMedia { id: lock }
  }

  IpcHandler {
    target: "harness"
    function pin(bus: string): void { MediaState.pinnedPlayer = bus }
  }

  readonly property string state: JSON.stringify({
    // every player the shell knows, noise too, so the driver steps only once the shell caught up
    seen: (Mpris.players ? Mpris.players.values : []).map(p => p.dbusName + "=" + p.playbackState),
    players: MediaState.players.map(p => p.dbusName + "=" + p.playbackState),
    player: MediaState.player ? MediaState.player.dbusName : "",
    pinned: MediaState.pinnedPlayer,
    shown: media.visible,
    playing: media.playing,
    line: media.line,
    title: media.title,
    artist: media.artist,
    album: media.album,
    artUrl: media.artUrl,
    lock: lock.mediaText,
    artAccent: MediaState.artAccent ? MediaState.artAccent.toString() : "",
    accent: MediaState.accent.toString(),
    themeAccent: Colors.accent.toString()
  })
  onStateChanged: console.log("STATE " + state)
  Component.onCompleted: console.log("STATE " + state)
}
"""


def build(src, out):
    """A copy of the tree with window types stubbed, the linger shortened, no network fetch and the lock's media
    properties lifted out of Lock.qml into a plain QtObject."""
    shutil.rmtree(out, ignore_errors=True)
    shutil.copytree(src, out)
    with open(os.path.join(out, "Ui/HoverPanel.qml"), "w") as f:
        f.write(HOVER_STUB)
    media_path = os.path.join(out, "plugins/bar/widgets/Media.qml")
    media = open(media_path).read()
    media, n = re.subn(r"(id: lingerTimer\s+interval: )30000", r"\g<1>%d" % LINGER_MS, media)
    assert n == 1, "Media.qml: lingerTimer interval not found"
    open(media_path, "w").write(media)
    state_path = os.path.join(out, "Commons/MediaState.qml")
    state = open(state_path).read()
    state, n = re.subn(r"curl -sfL", "false", state)
    assert n == 1, "MediaState.qml: art fetch not found"
    open(state_path, "w").write(state)
    lock = open(os.path.join(out, "plugins/lock/Lock.qml")).read()
    m = re.search(r"(?ms)^  readonly property var player: \{.*?^  \}\n(?:  readonly property string media\w+:[^\n]*\n)+", lock)
    assert m and "mediaText" in m.group(0), "Lock.qml: player and mediaText not found"
    with open(os.path.join(out, "plugins/bar/widgets/LockMedia.qml"), "w") as f:
        f.write("import QtQuick\nimport Quickshell.Services.Mpris\nimport qs.Commons\n\nQtObject {\n  id: root\n" + m.group(0) + "}\n")
    with open(os.path.join(out, "shell.qml"), "w") as f:
        f.write(SHELL)


def variant(v):
    if type(v).__module__ in ("dbus", "_dbus_bindings") or isinstance(v, dbus.Dictionary):
        return v
    if isinstance(v, bool):
        return dbus.Boolean(v)
    if isinstance(v, int):
        return dbus.Int64(v)
    if isinstance(v, float):
        return dbus.Double(v)
    if isinstance(v, list):
        return dbus.Array(v, signature="s")
    return dbus.String(v)


class FakePlayer(dbus.service.Object):
    """One MPRIS player on its own connection, so each has its own bus name and object."""

    def __init__(self, address, name, identity, status="Paused", meta=None, desktop=""):
        self.conn = dbus.bus.BusConnection(address)
        self.name = MPRIS + "." + name
        self.bus_name = dbus.service.BusName(self.name, bus=self.conn)
        self.root = {"Identity": identity, "DesktopEntry": desktop, "CanQuit": True, "CanRaise": False,
                     "HasTrackList": False, "SupportedUriSchemes": dbus.Array([], signature="s"),
                     "SupportedMimeTypes": dbus.Array([], signature="s")}
        self.player = {"PlaybackStatus": status, "Metadata": self.metadata(meta or {}), "Position": dbus.Int64(0),
                       "Rate": 1.0, "MinimumRate": 1.0, "MaximumRate": 1.0, "Volume": 1.0, "CanGoNext": True,
                       "CanGoPrevious": True, "CanPlay": True, "CanPause": True, "CanSeek": True, "CanControl": True,
                       "LoopStatus": "None", "Shuffle": False}
        self.calls = []
        super().__init__(self.conn, OBJ)

    @staticmethod
    def metadata(meta):
        return dbus.Dictionary({k: variant(v) for k, v in meta.items()}, signature="sv")

    def props(self, iface):
        return self.root if iface == MPRIS else self.player

    def update(self, **changes):
        if "Metadata" in changes:
            changes["Metadata"] = self.metadata(changes["Metadata"])
        self.player.update(changes)
        self.PropertiesChanged(PLAYER, {k: variant(v) for k, v in changes.items()}, [])

    def close(self):
        self.remove_from_connection()
        self.bus_name = None
        self.conn.close()

    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return variant(self.props(iface)[prop])

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return {k: variant(v) for k, v in self.props(iface).items()}

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, iface, prop, value):
        self.calls.append("Set " + prop)
        self.props(iface)[prop] = value
        self.PropertiesChanged(iface, {prop: value}, [])

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    @dbus.service.method(MPRIS)
    def Raise(self):
        self.calls.append("Raise")

    @dbus.service.method(MPRIS)
    def Quit(self):
        self.calls.append("Quit")

    def transport(self, name, status=None):
        self.calls.append(name)
        if status:
            self.update(PlaybackStatus=status)

    @dbus.service.method(PLAYER)
    def PlayPause(self):
        self.transport("PlayPause", "Paused" if self.player["PlaybackStatus"] == "Playing" else "Playing")

    @dbus.service.method(PLAYER)
    def Play(self):
        self.transport("Play", "Playing")

    @dbus.service.method(PLAYER)
    def Pause(self):
        self.transport("Pause", "Paused")

    @dbus.service.method(PLAYER)
    def Stop(self):
        self.transport("Stop", "Stopped")

    @dbus.service.method(PLAYER)
    def Next(self):
        self.transport("Next")

    @dbus.service.method(PLAYER)
    def Previous(self):
        self.transport("Previous")

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset):
        self.transport("Seek")

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track, position):
        self.transport("SetPosition")

    @dbus.service.method(PLAYER, in_signature="s")
    def OpenUri(self, uri):
        self.transport("OpenUri")


class Harness:
    def __init__(self, shell_dir):
        self.shell_dir = shell_dir
        self.address = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        self.players = {}
        self.lines = queue.Queue()
        self.log = []
        self.state = None
        self.failures = []
        self.qs = subprocess.Popen(["quickshell", "--no-color", "-p", shell_dir], stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.qs.stdout:
            self.lines.put(line.rstrip("\n"))
        self.lines.put(None)

    def pump(self, seconds):
        end = time.monotonic() + seconds
        ctx = GLib.MainContext.default()
        while True:
            while ctx.pending():
                ctx.iteration(False)
            try:
                line = self.lines.get(timeout=0.02)
            except queue.Empty:
                line = ""
            if line is None:
                raise SystemExit("quickshell exited:\n" + "\n".join(self.log[-40:]))
            if line:
                self.log.append(line)
                m = re.search(r"STATE (\{.*\})$", line)
                if m:
                    self.state = json.loads(m.group(1))
            if time.monotonic() >= end:
                return

    def wait(self, pred, seconds=SETTLE_S):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            self.pump(0.05)
            if self.state is not None and pred(self.state):
                return True
        return False

    def seen(self, name, status):
        """wait until the shell knows the player in that status: the start order and the list order follow the order
        the shell sees players in, not the order they joined the bus"""
        key = MPRIS + "." + name + "=" + str(STATUS[status])
        if not self.wait(lambda s: key in s["seen"]):
            self.fail("shell sees " + key, key, self.state and self.state["seen"])

    def add(self, name, identity, status="Paused", meta=None, desktop=""):
        self.players[name] = FakePlayer(self.address, name, identity, status, meta, desktop)
        self.seen(name, status)
        return self.players[name]

    def status(self, name, status):
        self.players[name].update(PlaybackStatus=status)
        self.seen(name, status)

    def remove(self, name):
        self.players.pop(name).close()

    def clear(self):
        for name in list(self.players):
            self.remove(name)
        self.ipc("harness", "pin", "")
        if not self.wait(lambda s: not s["seen"] and not s["players"] and not s["shown"] and not s["pinned"],
                         LINGER_MS / 1000 + SETTLE_S):
            self.fail("reset", "no players, hidden", self.state)

    def ipc(self, target, fn, *args):
        r = subprocess.run(["quickshell", "ipc", "-p", self.shell_dir, "call", target, fn, *args],
                           capture_output=True, text=True, timeout=10)
        self.pump(0.1)
        return r.stdout.strip()

    def fail(self, scenario, expected, actual):
        self.failures.append((scenario, expected, actual))
        print(f"FAIL {scenario}\n  expected: {expected}\n  actual:   {json.dumps(actual)}", flush=True)

    def expect(self, scenario, seconds=SETTLE_S, **want):
        ok = self.wait(lambda s: all(s.get(k) == v for k, v in want.items()), seconds)
        if not ok:
            self.fail(scenario, want, {k: self.state.get(k) for k in want} if self.state else None)
            return False
        print(f"ok   {scenario}", flush=True)
        return True

    def hold(self, scenario, seconds, since=None, **want):
        """want holds for the whole window, not just once; with since, the window ends seconds after that moment"""
        end = (since if since is not None else time.monotonic()) + seconds
        while time.monotonic() < end:
            self.pump(0.05)
            if not all(self.state.get(k) == v for k, v in want.items()):
                self.fail(scenario, want, {k: self.state.get(k) for k in want})
                return False
        print(f"ok   {scenario}", flush=True)
        return True


SONG = {"mpris:trackid": dbus.ObjectPath("/track/1"), "xesam:title": "Song A", "xesam:artist": ["Artist A"],
        "xesam:album": "Album A", "mpris:length": dbus.Int64(200_000_000), "mpris:artUrl": "file:///tmp/cover-a.jpg"}
YT = "https://www.youtube.com/watch?v=oYmREV6m-Fg"
FIREFOX = {"mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/firefox"),
           "xesam:title": "The Video - YouTube", "xesam:album": "", "xesam:artist": [""], "xesam:url": YT,
           "mpris:length": dbus.Int64(2641000000)}
PBI = {"kde:pid": dbus.Int32(4857), "mpris:artUrl": "file:///tmp/pbi-artwork.jpg",
       "mpris:length": dbus.Int64(2641071766), "mpris:trackid": dbus.ObjectPath("/org/kde/plasma/browser_integration/1337"),
       "xesam:artist": ["The Channel"], "xesam:title": "The Video", "xesam:url": YT}
SPOTIFY = {"mpris:trackid": dbus.String("/com/spotify/track/3OFYm7iUGkfejfsgKXfjdb"),
           "mpris:length": dbus.UInt64(174371000),
           "mpris:artUrl": "https://i.scdn.co/image/ab67616d0000b273c6109595f9a6434df44bc724",
           "xesam:album": "Rehab (Bonus Tracks Version)", "xesam:albumArtist": ["Electric Callboy"],
           "xesam:artist": ["Electric Callboy"], "xesam:autoRating": dbus.Double(0.4), "xesam:discNumber": dbus.Int32(1),
           "xesam:title": "Supernova", "xesam:trackNumber": dbus.Int32(3),
           "xesam:url": "https://open.spotify.com/track/3OFYm7iUGkfejfsgKXfjdb"}


def song(title, artist, **extra):
    return {**SONG, "xesam:title": title, "xesam:artist": [artist], **extra}


def cover(work, name, color):
    path = os.path.join(work, name + ".png")
    subprocess.run(["magick", "-size", "64x64", "xc:" + color, path], check=True)
    return "file://" + path


def scenarios(h, work):
    linger = LINGER_MS / 1000

    h.expect("nothing: bar hidden, no lock line", players=[], player="", shown=False, lock="")

    h.clear()
    h.add("mpv", "mpv", "Paused", SONG, "mpv")
    h.expect("one paused: chosen but bar hidden, no lock line", player=MPRIS + ".mpv", shown=False, playing=False,
             lock="")

    h.clear()
    h.add("mpv", "mpv", "Playing", SONG, "mpv")
    h.expect("one playing: bar and lock show the track", player=MPRIS + ".mpv", shown=True, playing=True,
             line="Song A :: Artist A", album="Album A", artUrl="file:///tmp/cover-a.jpg", lock="> Artist A :: Song A")

    h.clear()
    h.add("firefox.instance_1_58", "Mozilla firefox", "Playing", FIREFOX, "firefox")
    h.add("plasma-browser-integration", "Mozilla Firefox", "Paused", PBI, "firefox")
    h.expect("firefox playing, pbi twin paused: folded to the playing one",
             players=[MPRIS + ".firefox.instance_1_58=1"], player=MPRIS + ".firefox.instance_1_58", shown=True,
             playing=True, line="The Video - YouTube", artUrl="https://i.ytimg.com/vi/oYmREV6m-Fg/mqdefault.jpg",
             lock="> The Video - YouTube")
    h.status("plasma-browser-integration", "Playing")
    h.expect("firefox and pbi twin both playing: the richer twin, lock agrees",
             players=[MPRIS + ".plasma-browser-integration=1"], player=MPRIS + ".plasma-browser-integration",
             shown=True, line="The Video :: The Channel", artUrl="file:///tmp/pbi-artwork.jpg",
             lock="> The Channel :: The Video")
    h.status("firefox.instance_1_58", "Paused")
    h.status("plasma-browser-integration", "Paused")
    h.expect("firefox and pbi twin both paused: the richer twin, lock empty",
             players=[MPRIS + ".plasma-browser-integration=2"], playing=False, lock="")

    h.clear()
    h.add("firefox.instance_1_58", "Mozilla firefox", "Playing",
          {**FIREFOX, "xesam:artist": ["https://www.youtube.com"], "xesam:album": "https://www.youtube.com"}, "firefox")
    h.expect("tab with its site as artist and album: bar and lock drop it", shown=True, line="The Video - YouTube",
             artist="", album="", lock="> The Video - YouTube")

    h.clear()
    h.add("mpv.instance1", "mpv", "Paused", song("First", "One"), "mpv")
    h.add("mpv.instance2", "mpv", "Playing", song("Second", "Two"), "mpv")
    h.expect("two mpv, same identity: both listed, the playing one shown",
             players=[MPRIS + ".mpv.instance1=2", MPRIS + ".mpv.instance2=1"], player=MPRIS + ".mpv.instance2",
             shown=True, line="Second :: Two", lock="> Two :: Second")

    h.clear()
    h.add("mpv", "mpv", "Playing", SONG, "mpv")
    h.expect("vanish setup", shown=True)
    h.remove("mpv")
    h.expect("player vanishing while shown: bar hidden at once, lock empty", players=[], player="", shown=False,
             line="", lock="")

    h.clear()
    h.add("mpv", "mpv", "Paused", song("Left Open", "Idle"), "mpv")
    h.add("spotify", "Spotify", "Playing", SPOTIFY, "spotify")
    h.expect("vanish-other setup", player=MPRIS + ".spotify", shown=True)
    h.remove("spotify")
    h.expect("playing player vanishing, a paused one left: falls back to the paused one", player=MPRIS + ".mpv",
             playing=False, lock="")
    h.expect("... then hides after the linger", shown=False, seconds=linger + SETTLE_S)

    h.clear()
    h.add("mpv", "mpv", "Playing", song("Pinned Song", "Pin"), "mpv")
    h.add("spotify", "Spotify", "Playing", SPOTIFY, "spotify")
    h.expect("pin-playing setup", players=[MPRIS + ".mpv=1", MPRIS + ".spotify=1"])
    h.ipc("harness", "pin", MPRIS + ".mpv")
    h.expect("pinned player shown over another playing one", pinned=MPRIS + ".mpv", player=MPRIS + ".mpv",
             shown=True, line="Pinned Song :: Pin")
    h.remove("mpv")
    h.expect("pinned player vanishing: pin cleared, the playing one shown", pinned="", player=MPRIS + ".spotify",
             shown=True, line="Supernova :: Electric Callboy")

    h.clear()
    h.add("spotify", "Spotify", "Playing", SPOTIFY, "spotify")
    h.add("mpv", "mpv", "Paused", song("Paused Pin", "Pin"), "mpv")
    h.add("vlc", "VLC media player", "Paused", song("Newcomer", "Vlc"), "vlc")
    h.expect("pin-paused setup", player=MPRIS + ".spotify", shown=True,
             players=[MPRIS + ".spotify=1", MPRIS + ".mpv=2", MPRIS + ".vlc=2"])
    h.ipc("harness", "pin", MPRIS + ".mpv")
    h.expect("paused player pinned while another plays: bar shows the pin, lock the playing one",
             player=MPRIS + ".mpv", pinned=MPRIS + ".mpv", line="Paused Pin :: Pin", lock="> Electric Callboy :: Supernova")
    h.hold("paused pin stays shown past the linger while something plays", linger + 1, shown=True)
    h.status("spotify", "Paused")
    h.status("spotify", "Playing")
    h.hold("another player starting: pin kept", 1, pinned=MPRIS + ".mpv", player=MPRIS + ".mpv")
    h.ipc("harness", "pin", "")
    h.expect("pin clicked off: the playing one shown", pinned="", player=MPRIS + ".spotify")
    h.ipc("harness", "pin", MPRIS + ".vlc")
    h.status("vlc", "Playing")
    h.hold("the pinned player itself starting: pin kept", 1, pinned=MPRIS + ".vlc", player=MPRIS + ".vlc")

    h.clear()
    h.add("mpv", "mpv", "Playing", song("Older", "Mpv"), "mpv")
    h.add("spotify", "Spotify", "Playing", SPOTIFY, "spotify")
    h.expect("two-playing setup: the later starter shown", player=MPRIS + ".spotify")
    h.status("spotify", "Paused")
    h.expect("shown one paused while another plays: switches to the playing one", player=MPRIS + ".mpv",
             playing=True, line="Older :: Mpv")

    h.clear()
    h.add("mpv", "mpv", "Playing", SONG, "mpv")
    h.expect("pause setup", shown=True)
    paused = time.monotonic()
    h.status("mpv", "Paused")
    h.expect("playing to paused: lock line gone at once", playing=False, lock="")
    # measured from the pause, which the linger also counts from, so a slow step above never runs the window past it
    h.hold("playing to paused: bar lingers", linger * 0.6, since=paused, shown=True, line="Song A :: Artist A")
    h.expect("playing to paused: bar hides after the linger", shown=False, seconds=linger + SETTLE_S)
    h.status("mpv", "Playing")
    h.expect("paused to playing again: shown", shown=True, lock="> Artist A :: Song A")

    h.clear()
    h.add("mpv", "mpv", "Playing", SONG, "mpv")
    h.expect("track setup", shown=True)
    h.players["mpv"].update(Metadata=song("Song B", "Artist B", **{"mpris:artUrl": "file:///tmp/cover-b.jpg",
                                                                   "xesam:album": "Album B"}))
    h.expect("track change: bar and lock follow", line="Song B :: Artist B", album="Album B",
             artUrl="file:///tmp/cover-b.jpg", lock="> Artist B :: Song B")

    h.clear()
    meta = dict(SONG)
    del meta["mpris:artUrl"]
    h.add("mpv", "mpv", "Playing", meta, "mpv")
    h.expect("missing art: no art url", shown=True, artUrl="")
    h.players["mpv"].update(Metadata={**meta, "mpris:artUrl": "file:///"})
    h.expect("bare file:/// art: no art url", artUrl="")
    h.players["mpv"].update(Metadata={**meta, "mpris:artUrl": "file:///tmp/covers/"})
    h.expect("directory art: no art url", artUrl="")

    # an orange that already clears the stroke and text contrast on the default dark background, so it shows unchanged
    orange = cover(work, "orange", ART_ORANGE)
    black = cover(work, "black", "#000000")
    h.clear()
    h.expect("no player: theme accent", artAccent="", accent=THEME_ACCENT, themeAccent=THEME_ACCENT)
    h.add("mpv", "mpv", "Playing", song("Orange", "Cover", **{"mpris:artUrl": orange}), "mpv")
    h.expect("playing with a coloured cover: accent from the art", artUrl=orange, artAccent=ART_ORANGE.lower(),
             accent=ART_ORANGE.lower())
    h.status("mpv", "Paused")
    h.expect("paused: back to the theme accent", playing=False, artAccent="", accent=THEME_ACCENT)
    h.status("mpv", "Playing")
    h.expect("playing again: the art accent returns", artAccent=ART_ORANGE.lower(), accent=ART_ORANGE.lower())
    h.players["mpv"].update(Metadata=song("Black", "Cover", **{"mpris:artUrl": black}))
    h.expect("cover without a colour: theme accent", artUrl=black, artAccent="", accent=THEME_ACCENT)
    h.players["mpv"].update(Metadata=song("Orange", "Cover", **{"mpris:artUrl": orange}))
    h.expect("art accent setup", artAccent=ART_ORANGE.lower())
    h.players["mpv"].update(Metadata=meta)
    h.expect("track without art: theme accent", artUrl="", artAccent="", accent=THEME_ACCENT)

    h.clear()
    h.add("spotify", "Spotify", "Playing", SPOTIFY, "spotify")
    h.expect("spotify metadata: string trackid, uint64 length", shown=True, line="Supernova :: Electric Callboy",
             album="Rehab (Bonus Tracks Version)",
             artUrl="https://i.scdn.co/image/ab67616d0000b273c6109595f9a6434df44bc724",
             lock="> Electric Callboy :: Supernova")
    h.add("playerctld", "Spotify", "Playing", SPOTIFY, "spotify")
    h.expect("playerctld proxy ignored by the bar", players=[MPRIS + ".spotify=1"], player=MPRIS + ".spotify")

    h.clear()
    h.add("mpv", "mpv", "Playing", SONG, "mpv")
    h.expect("media key setup", shown=True)
    out = h.ipc("media", "playPause")
    h.expect("media key pauses the shown player", playing=False, lock="")
    if "media-pause" not in out:
        h.fail("media key osd payload", "media-pause icon", out)
    h.clear()
    h.add("mpv", "mpv", "Paused", song("Title Only", ""), "mpv")
    h.status("mpv", "Playing")
    h.expect("title without artist: no separator", line="Title Only", lock="> Title Only")
    h.clear()
    h.add("vlc", "VLC media player", "Playing", {"mpris:trackid": dbus.ObjectPath("/t/1")}, "vlc")
    h.expect("no title: bar names the player, lock empty", shown=True, line="VLC media player", lock="")
    h.status("vlc", "Paused")
    h.expect("no title and paused: dropped as noise", players=[], player="")

    selection(h)


def selection(h):
    """the shown player: pinned, else the playing one that started last, else the one shown before, else the one that
    played last; noise never listed"""
    h.clear()
    h.add("spotify", "Spotify", "Playing", SPOTIFY, "spotify")
    h.add("mpv", "mpv", "Paused", song("Later", "Mpv"), "mpv")
    h.expect("select setup", player=MPRIS + ".spotify")
    h.status("mpv", "Playing")
    h.expect("two playing: the one started last", player=MPRIS + ".mpv", line="Later :: Mpv")
    h.status("spotify", "Paused")
    h.status("spotify", "Playing")
    h.expect("restarted player: shown again", player=MPRIS + ".spotify", line="Supernova :: Electric Callboy")
    h.status("spotify", "Paused")
    h.expect("shown one paused, the other plays: the playing one", player=MPRIS + ".mpv")
    h.status("mpv", "Paused")
    h.hold("all paused: the last shown kept", 1, player=MPRIS + ".mpv")

    h.clear()
    h.add("vlc", "VLC media player", "Paused", song("Never Played", "Vlc"), "vlc")
    h.add("mpv", "mpv", "Playing", song("Played", "Mpv"), "mpv")
    h.expect("fallback setup", player=MPRIS + ".mpv")
    h.status("mpv", "Paused")
    h.add("spotify", "Spotify", "Playing", SPOTIFY, "spotify")
    h.expect("fallback setup: newcomer plays", player=MPRIS + ".spotify")
    h.remove("spotify")
    h.expect("shown player vanishing, all left paused: the one that played last", player=MPRIS + ".mpv",
             line="Played :: Mpv")

    h.clear()
    h.add("spotify", "Spotify", "Paused", SPOTIFY, "spotify")
    h.add("obs", "OBS Studio", "Playing", song("Browser Source", "Obs"), "com.obsproject.Studio")
    h.add("chromium.instance88469", "ZapZap", "Stopped",
          {"mpris:trackid": dbus.ObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack"), "xesam:title": "",
           "xesam:artist": [""], "mpris:artUrl": "", "mpris:length": dbus.Int64(0)})
    h.expect("noise: OBS and an idle webview never listed, the paused real player shown",
             players=[MPRIS + ".spotify=2"], player=MPRIS + ".spotify", playing=False, lock="")
    h.players["chromium.instance88469"].update(PlaybackStatus="Playing", Metadata=song("Voice Note", "Chat"))
    h.expect("a webview that starts playing media: listed and shown", player=MPRIS + ".chromium.instance88469",
             line="Voice Note :: Chat")


def main():
    src, work = sys.argv[1], sys.argv[2]
    shell_dir = os.path.join(work, "shell")
    build(src, shell_dir)
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    h = Harness(shell_dir)
    try:
        if not h.wait(lambda s: True, 60):
            raise SystemExit("no STATE from quickshell:\n" + "\n".join(h.log[-60:]))
        scenarios(h, work)
    finally:
        for name in list(h.players):
            h.remove(name)
        h.qs.terminate()
        try:
            h.qs.wait(5)
        except subprocess.TimeoutExpired:
            h.qs.kill()
    errors = [l for l in h.log if re.search(r"\bERROR\b|TypeError|ReferenceError|is not a type|Unable to assign", l)
              and "pipewire context" not in l]
    if errors:
        h.failures.append(("qml errors", "none", errors))
        print("qml errors:\n  " + "\n  ".join(errors[:30]))
    print(f"{len(h.failures)} failed")
    sys.exit(1 if h.failures else 0)


if __name__ == "__main__":
    main()
'#

def main [] {
    let missing = [quickshell dbus-run-session python3 magick] | where { which $in | is-empty }
    let bindings = if ($missing | is-empty) { ^python3 -I -c "import dbus.mainloop.glib, gi" | complete | get exit_code } else { 1 }
    if ($missing | is-not-empty) or $bindings != 0 {
        print -e $"media.test.nu: warn: skipped, missing ($missing | append (if $bindings != 0 { [python-dbus] } else { [] }) | uniq | str join ', ')"
        return
    }
    let dir = mktemp --directory --tmpdir media-test-XXXXXX
    # sockets go in the runtime dir: a short path, never the temp dir's
    let rt = mktemp --directory --tmpdir-path ($env.XDG_RUNTIME_DIR? | default "/tmp") qsm-XXXXXX
    # remove both dirs whether the run succeeds or a step throws
    let outcome = try {
        $DRIVER | save ($dir | path join driver.py)
        for d in [state cache config data] { mkdir ($dir | path join $d) }
        (^env -i $"HOME=($env.HOME)" $"PATH=($env.PATH | str join ':')" LANG=C.UTF-8 $"XDG_RUNTIME_DIR=($rt)"
            QT_QPA_PLATFORM=offscreen GIO_USE_VFS=local GVFS_DISABLE_FUSE=1
            $"XDG_STATE_HOME=($dir)/state" $"XDG_CACHE_HOME=($dir)/cache" $"XDG_CONFIG_HOME=($dir)/config"
            $"XDG_DATA_HOME=($dir)/data"
            timeout 300 dbus-run-session -- python3 -I ($dir | path join driver.py) $SHELL $dir) | complete
    } catch {|e| {failed: $e.msg} }
    rm --recursive --force $dir $rt
    if ($outcome | get --optional failed) != null { error make {msg: $outcome.failed} }
    if $outcome.exit_code != 0 { error make {msg: $"media scenarios failed\n($outcome.stdout)($outcome.stderr)"} }
}
