#!/usr/bin/env python3
"""Streams OBS Studio's stream/record state and health as one JSON line per update.

LONG-LIVED, not one-shot. Obs.qml reads this with a SplitParser, the same shape
as system-stats.sh and `nmcli monitor`: one process for the life of the shell
rather than a fresh websocket handshake every second. A handshake per poll would
also mean an auth round trip per poll, which OBS logs as a new session each time.

CONNECTION DETAILS ARE NOT CONFIGURED HERE. The port and password are read from
obs-websocket's own config at
~/.config/obs-studio/plugin_config/obs-websocket/config.json — the same file the
OBS UI writes from Tools -> WebSocket Server Settings. There is deliberately no
second place to set them: a copy in this repo would be a password in git, and a
copy anywhere else is a copy to be wrong.

COMMANDS COME BACK IN ON STDIN, one JSON object per line — the reverse channel
of the same pipe the widget already reads. That is why this is a persistent
process rather than a series of one-shot calls: a command issued over an
already-authenticated session is a single request, where a one-shot would pay
for a fresh websocket handshake and auth round trip per button press, and OBS
logs each of those as a new session.

  {"cmd": "setScene", "scene": "Gameplay"}
  {"cmd": "toggleStream"}      {"cmd": "toggleRecord"}
  {"cmd": "toggleRecordPause"}

Commands are fire-and-forget: the reply that matters is the next status line,
because that is what the UI actually renders. A rejected request is logged to
stderr and otherwise ignored.

WHEN OBS IS NOT RUNNING this prints `{"connected": false}` and retries. That is
the normal state, not an error: the widget hides itself, and the moment OBS
starts the next connect attempt succeeds. Backoff is capped low (5s) because the
interesting transition — "I just hit Start Streaming" — is one a status widget
should not be five minutes late to.

Requires python-websocket-client (the `websocket` module), which is packaged on
Arch as python-websocket-client.
"""

import base64
import hashlib
import json
import os
import pathlib
import select
import sys
import time

try:
    import websocket  # python-websocket-client
except ImportError:
    print(json.dumps({"connected": False, "error": "python-websocket-client not installed"}),
          flush=True)
    sys.exit(0)

CONFIG = (pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or (pathlib.Path.home() / ".config"))
          / "obs-studio/plugin_config/obs-websocket/config.json")

# obs-websocket 5.x EventSubscription bit flags. Only what is actually rendered:
# subscribing to Inputs or SceneItems would wake this process on every volume
# nudge and every source drag for data nothing here displays.
SUB_GENERAL = 1 << 0
SUB_SCENES = 1 << 2
SUB_OUTPUTS = 1 << 6
SUBSCRIPTIONS = SUB_GENERAL | SUB_SCENES | SUB_OUTPUTS

# While live, the numbers that matter (bitrate, dropped frames) move every
# second. While idle nothing moves at all, and the only reason to ask is to
# notice a scene change, so the idle poll is deliberately lazy.
POLL_ACTIVE = 1.0
POLL_IDLE = 5.0

RECONNECT_MIN = 1.0
RECONNECT_MAX = 5.0


def read_config():
    """Port and password from obs-websocket's own config, or None if it is off."""
    try:
        cfg = json.loads(CONFIG.read_text())
    except Exception:
        return None
    if not cfg.get("server_enabled"):
        return None
    return {
        "port": int(cfg.get("server_port") or 4455),
        "password": cfg.get("server_password") or "",
        "auth_required": bool(cfg.get("auth_required", True)),
    }


def auth_response(password, salt, challenge):
    """obs-websocket 5.x auth: base64(sha256(base64(sha256(password+salt)) + challenge))."""
    secret = base64.b64encode(hashlib.sha256((password + salt).encode()).digest()).decode()
    return base64.b64encode(hashlib.sha256((secret + challenge).encode()).digest()).decode()


class Session:
    def __init__(self, ws):
        self.ws = ws
        self._next_id = 0

    def request(self, request_type, data=None):
        """Send one request and return its response payload.

        Responses are matched by requestId rather than assumed to arrive next:
        an event can land between the request and its response, and reading the
        event as the response is how this kind of client goes subtly wrong.
        Events seen while waiting are returned to the caller's queue.
        """
        self._next_id += 1
        request_id = str(self._next_id)
        self.ws.send(json.dumps({
            "op": 6,
            "d": {"requestType": request_type, "requestId": request_id,
                  "requestData": data or {}},
        }))
        stray_events = []
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            msg = json.loads(self.ws.recv())
            if msg.get("op") == 7 and msg["d"].get("requestId") == request_id:
                status = msg["d"].get("requestStatus") or {}
                if not status.get("result"):
                    return None, stray_events
                return msg["d"].get("responseData") or {}, stray_events
            if msg.get("op") == 5:
                stray_events.append(msg["d"])
        return None, stray_events


def connect(conf):
    ws = websocket.create_connection("ws://127.0.0.1:%d" % conf["port"], timeout=6)
    hello = json.loads(ws.recv())
    if hello.get("op") != 0:
        ws.close()
        raise RuntimeError("unexpected greeting")

    identify = {"rpcVersion": hello["d"].get("rpcVersion", 1),
                "eventSubscriptions": SUBSCRIPTIONS}
    auth = hello["d"].get("authentication")
    if auth:
        if not conf["password"]:
            ws.close()
            raise RuntimeError("auth required but no password in config")
        identify["authentication"] = auth_response(
            conf["password"], auth["salt"], auth["challenge"])

    ws.send(json.dumps({"op": 1, "d": identify}))
    identified = json.loads(ws.recv())
    if identified.get("op") != 2:
        ws.close()
        raise RuntimeError("identify rejected")
    return ws


def timecode_seconds(timecode):
    """OBS timecodes are "HH:MM:SS.mmm". Emitted as seconds so the widget can
    format them however it likes without parsing strings."""
    try:
        head, _, _ = str(timecode or "").partition(".")
        parts = [int(p) for p in head.split(":")]
        while len(parts) < 3:
            parts.insert(0, 0)
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    except Exception:
        return 0


def snapshot(session):
    stats, _ = session.request("GetStats")
    stream, _ = session.request("GetStreamStatus")
    record, _ = session.request("GetRecordStatus")
    scene, _ = session.request("GetCurrentProgramScene")
    scenes, _ = session.request("GetSceneList")

    stats = stats or {}
    stream = stream or {}
    record = record or {}
    scene = scene or {}
    scenes = scenes or {}

    # OBS returns the scene list in reverse UI order (bottom of the list
    # first), so reverse it back — a scene switcher whose buttons are upside
    # down relative to OBS itself is worse than no switcher.
    scene_names = [str(s.get("sceneName", ""))
                   for s in reversed(scenes.get("scenes") or [])]
    scene_names = [n for n in scene_names if n]

    sent = int(stream.get("outputTotalFrames") or 0)
    skipped = int(stream.get("outputSkippedFrames") or 0)

    return {
        "connected": True,
        "streaming": bool(stream.get("outputActive")),
        "streamReconnecting": bool(stream.get("outputReconnecting")),
        "recording": bool(record.get("outputActive")),
        "recordPaused": bool(record.get("outputPaused")),

        "streamSeconds": timecode_seconds(stream.get("outputTimecode")),
        "recordSeconds": timecode_seconds(record.get("outputTimecode")),

        # OBS reports bytes for the whole session and a congestion figure; the
        # per-second bitrate people actually quote is derived in the widget from
        # successive samples, so both halves are published here.
        "streamBytes": int(stream.get("outputBytes") or 0),
        "recordBytes": int(record.get("outputBytes") or 0),
        "congestion": round(float(stream.get("outputCongestion") or 0.0), 3),

        # Dropped frames are the number that decides whether a stream is healthy.
        "droppedFrames": skipped,
        "totalFrames": sent,
        "dropPct": round(skipped * 100.0 / sent, 2) if sent else 0.0,

        "fps": round(float(stats.get("activeFps") or 0.0), 1),
        "cpu": round(float(stats.get("cpuUsage") or 0.0), 1),
        "memMb": round(float(stats.get("memoryUsage") or 0.0), 1),
        "freeDiskMb": round(float(stats.get("availableDiskSpace") or 0.0), 1),
        "frameTimeMs": round(float(stats.get("averageFrameRenderTime") or 0.0), 2),
        # Render skips mean the machine cannot draw fast enough; encoder skips
        # mean it cannot encode fast enough. Different fixes, so not summed.
        "renderSkipped": int(stats.get("renderSkippedFrames") or 0),
        "renderTotal": int(stats.get("renderTotalFrames") or 0),
        "encoderSkipped": int(stats.get("outputSkippedFrames") or 0),
        "encoderTotal": int(stats.get("outputTotalFrames") or 0),

        "scene": str(scene.get("currentProgramSceneName") or ""),
        "scenes": scene_names,
    }


_last_line = None


def emit(payload):
    global _last_line
    line = json.dumps(payload)
    # Identical to the last line means nothing moved — OBS open but idle, where
    # the five-second poll returns the same scene name forever. Re-printing it
    # costs the shell a JSON parse and a round of property writes per poll for
    # no change at all.
    #
    # This one check also covers the reconnect loop, which runs every second or
    # so while OBS is closed: its repeated {"connected": false} collapses to a
    # single line. An earlier version suppressed on connected-ness instead, and
    # that swallowed every *later* disconnect payload whose error differed —
    # "obs-websocket disabled" never reached the widget at all, because the
    # startup {"connected": false} had already latched the state off.
    if line == _last_line:
        return
    _last_line = line
    print(line, flush=True)


# requestType per command, and which payload key it carries. Kept as a table
# rather than an if-chain so the set of things the widget is allowed to do is
# one readable list — this is the only path from the desktop into OBS.
COMMANDS = {
    "toggleStream": ("ToggleStream", None),
    "startStream": ("StartStream", None),
    "stopStream": ("StopStream", None),
    "toggleRecord": ("ToggleRecord", None),
    "startRecord": ("StartRecord", None),
    "stopRecord": ("StopRecord", None),
    "toggleRecordPause": ("ToggleRecordPause", None),
    "setScene": ("SetCurrentProgramScene", "sceneName"),
}


def handle_command(session, line):
    """Apply one stdin command. Returns True if a status re-poll is warranted."""
    try:
        msg = json.loads(line)
    except Exception:
        return False
    entry = COMMANDS.get(str(msg.get("cmd", "")))
    if not entry:
        return False
    request_type, data_key = entry
    data = None
    if data_key:
        value = msg.get("scene")
        if not value:
            return False
        data = {data_key: str(value)}
    result, _ = session.request(request_type, data)
    if result is None:
        print("obs-status: %s rejected" % request_type, file=sys.stderr, flush=True)
    # Re-poll either way. A rejected toggle still means the UI's idea of the
    # state was wrong, and refreshing is how it finds out.
    return True


def run_session(conf):
    ws = connect(conf)
    session = Session(ws)
    # Blocking recv would hold the loop past its poll deadline; a short timeout
    # turns the socket into "deliver an event if one is ready" so events and
    # polling can share one thread without either starving the other.
    ws.settimeout(0.25)

    last_poll = 0.0
    active = False
    try:
        while True:
            interval = POLL_ACTIVE if active else POLL_IDLE
            now = time.monotonic()
            if now - last_poll >= interval:
                ws.settimeout(6)
                state = snapshot(session)
                ws.settimeout(0.25)
                active = state["streaming"] or state["recording"]
                emit(state)
                last_poll = time.monotonic()

            # Commands first: a button press must not wait out the socket
            # timeout before it is sent. select with a zero timeout makes this
            # a non-blocking peek, so the loop keeps its own cadence.
            while select.select([sys.stdin], [], [], 0)[0]:
                line = sys.stdin.readline()
                if not line:
                    # stdin closed — the shell tore the widget down. Exit
                    # rather than spinning on a dead descriptor forever.
                    return
                ws.settimeout(6)
                try:
                    if handle_command(session, line):
                        last_poll = 0.0
                finally:
                    ws.settimeout(0.25)

            try:
                msg = json.loads(ws.recv())
            except websocket.WebSocketTimeoutException:
                continue
            except (ValueError, TypeError):
                continue

            # Any output or scene change makes the cached snapshot stale, so
            # re-poll immediately rather than waiting out the interval. This is
            # what makes hitting Start Streaming show up at once instead of up
            # to five seconds later.
            if msg.get("op") == 5:
                event_type = msg["d"].get("eventType", "")
                if event_type.startswith(("StreamState", "RecordState",
                                          "CurrentProgramScene", "Exit")):
                    last_poll = 0.0
    finally:
        try:
            ws.close()
        except Exception:
            pass


def main():
    backoff = RECONNECT_MIN
    # Announce the starting state once so the widget has something to bind to
    # before OBS is ever opened, rather than staying at its uninitialised
    # default until the first successful connection.
    emit({"connected": False})
    while True:
        conf = read_config()
        if conf is None:
            # Distinct from "OBS is closed": the server is switched off (or
            # never enabled), and no amount of retrying will change that until
            # someone edits the config. Say which, so the panel can too.
            emit({"connected": False, "error": "obs-websocket disabled"})
            time.sleep(RECONNECT_MAX)
            continue
        try:
            run_session(conf)
        except Exception as exc:
            emit({"connected": False, "error": str(exc)[:120]})
            time.sleep(backoff)
            backoff = min(RECONNECT_MAX, backoff * 1.6)
        else:
            backoff = RECONNECT_MIN


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
