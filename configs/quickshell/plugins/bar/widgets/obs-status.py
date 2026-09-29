#!/usr/bin/env python3
"""Streams OBS state as JSON lines and applies commands read from stdin."""

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

# obs-websocket 5.x EventSubscription bit flags.
SUB_GENERAL = 1 << 0
SUB_SCENES = 1 << 2
SUB_INPUTS = 1 << 3
SUB_OUTPUTS = 1 << 6
SUBSCRIPTIONS = SUB_GENERAL | SUB_SCENES | SUB_INPUTS | SUB_OUTPUTS

# panel label -> obs input name
MUTE_SOURCES = {
    "Mic": "Mic/Aux",
    "Desktop": "Desktop Audio",
    "Chromium": "Chromium Audio",
    "Discord": "Discord Audio",
    "Firefox": "Firefox Audio",
    "Spotify": "Spotify Audio",
}

# poll faster while live
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
        """Send one request; the reply is matched by requestId since events interleave."""
        self._next_id += 1
        request_id = str(self._next_id)
        self.ws.send(json.dumps({
            "op": 6,
            "d": {"requestType": request_type, "requestId": request_id,
                  "requestData": data or {}},
        }))
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            msg = json.loads(self.ws.recv())
            if msg.get("op") == 7 and msg["d"].get("requestId") == request_id:
                status = msg["d"].get("requestStatus") or {}
                if not status.get("result"):
                    return None
                return msg["d"].get("responseData") or {}
        return None


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
    """Timecode "HH:MM:SS.mmm" -> seconds."""
    try:
        head, _, _ = str(timecode or "").partition(".")
        parts = [int(p) for p in head.split(":")]
        while len(parts) < 3:
            parts.insert(0, 0)
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    except Exception:
        return 0


def poll_mutes(session):
    mutes = {}
    for label, input_name in MUTE_SOURCES.items():
        result = session.request("GetInputMute", {"inputName": input_name})
        if result is not None:
            mutes[label] = bool(result.get("inputMuted"))
    return mutes


def snapshot(session):
    stats = session.request("GetStats")
    stream = session.request("GetStreamStatus")
    record = session.request("GetRecordStatus")
    scene = session.request("GetCurrentProgramScene")
    scenes = session.request("GetSceneList")
    mutes = poll_mutes(session)

    stats = stats or {}
    stream = stream or {}
    record = record or {}
    scene = scene or {}
    scenes = scenes or {}

    # obs lists scenes bottom first
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

        "streamBytes": int(stream.get("outputBytes") or 0),
        "recordBytes": int(record.get("outputBytes") or 0),
        "congestion": round(float(stream.get("outputCongestion") or 0.0), 3),

        "droppedFrames": skipped,
        "dropPct": round(skipped * 100.0 / sent, 2) if sent else 0.0,

        "fps": round(float(stats.get("activeFps") or 0.0), 1),
        "cpu": round(float(stats.get("cpuUsage") or 0.0), 1),
        "memMb": round(float(stats.get("memoryUsage") or 0.0), 1),
        "freeDiskMb": round(float(stats.get("availableDiskSpace") or 0.0), 1),
        "frameTimeMs": round(float(stats.get("averageFrameRenderTime") or 0.0), 2),
        "renderSkipped": int(stats.get("renderSkippedFrames") or 0),
        "renderTotal": int(stats.get("renderTotalFrames") or 0),
        "encoderSkipped": int(stats.get("outputSkippedFrames") or 0),
        "encoderTotal": int(stats.get("outputTotalFrames") or 0),

        "scene": str(scene.get("currentProgramSceneName") or ""),
        "scenes": scene_names,

        "mutes": mutes,
    }


_last_line = None


def emit(payload):
    global _last_line
    line = json.dumps(payload)
    # skip unchanged lines
    if line == _last_line:
        return
    _last_line = line
    print(line, flush=True)


# cmd -> (requestType, payload key)
COMMANDS = {
    "toggleStream": ("ToggleStream", None),
    "toggleRecord": ("ToggleRecord", None),
    "toggleRecordPause": ("ToggleRecordPause", None),
    "setScene": ("SetCurrentProgramScene", "sceneName"),
}


def handle_command(session, line):
    """Apply one stdin command. Returns True if a status re-poll is warranted."""
    try:
        msg = json.loads(line)
    except Exception:
        return False
    cmd = str(msg.get("cmd", ""))

    # needs the label -> input name translation
    if cmd == "toggleMute":
        label = str(msg.get("source") or "")
        input_name = MUTE_SOURCES.get(label)
        if not input_name:
            return False
        result = session.request("ToggleInputMute", {"inputName": input_name})
        if result is None:
            print("obs-status: ToggleInputMute(%s) rejected" % input_name,
                  file=sys.stderr, flush=True)
        return True

    entry = COMMANDS.get(cmd)
    if not entry:
        return False
    request_type, data_key = entry
    data = None
    if data_key:
        value = msg.get("scene")
        if not value:
            return False
        data = {data_key: str(value)}
    result = session.request(request_type, data)
    if result is None:
        print("obs-status: %s rejected" % request_type, file=sys.stderr, flush=True)
    return True


def run_session(conf):
    ws = connect(conf)
    session = Session(ws)
    # short timeout so events and polling share one thread
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

            # commands first so a click does not wait out the socket timeout
            while select.select([sys.stdin], [], [], 0)[0]:
                line = sys.stdin.readline()
                if not line:
                    # stdin closed, the widget is gone
                    sys.exit(0)
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

            # output or scene change, re-poll now
            if msg.get("op") == 5:
                event_type = msg["d"].get("eventType", "")
                if event_type.startswith(("StreamState", "RecordState",
                                          "CurrentProgramScene", "Exit",
                                          "InputMuteStateChanged")):
                    last_poll = 0.0
    finally:
        try:
            ws.close()
        except Exception:
            pass


def main():
    backoff = RECONNECT_MIN
    emit({"connected": False})
    while True:
        conf = read_config()
        if conf is None:
            # server disabled in the obs config
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
            # obs closed the socket itself
            backoff = RECONNECT_MIN
            time.sleep(backoff)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
