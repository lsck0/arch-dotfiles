#!/usr/bin/env python3
"""Forwards ntfy topic messages to the desktop notification server.

Server and topics are read from the homelab source: every
`"https://<server>/${var}"` URL there, with `var` resolved in the same file.
Alertmanager and Grafana post their raw webhook JSON to ntfy, so those payloads
are summarised instead of shown verbatim.
"""

import html
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HOMELAB_DIR = os.environ.get("HOMELAB_DIR", os.path.expanduser("~/projects/homelab"))
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "ntfy-notify")
LAST_ID = os.path.join(STATE_DIR, "last-id")
# Alert group key -> the notification id currently on screen for it.
OPEN_ALERTS = os.path.join(STATE_DIR, "open-alerts.json")
# Messages missed while offline are replayed, but not a backlog older than this.
MAX_REPLAY_S = 3600


def subscriptions():
    """{server: [topics]} from the homelab's own publisher configuration."""
    found = {}
    instances = os.path.join(HOMELAB_DIR, "src", "instances")
    try:
        names = sorted(os.listdir(instances))
    except OSError:
        return found
    for name in names:
        if not name.endswith(".nix"):
            continue
        with open(os.path.join(instances, name)) as fh:
            text = fh.read()
        for server, var in re.findall(r'(https://[^/"\s$]+)/\$\{(\w+)\}', text):
            value = re.search(r"\b%s\s*=\s*\"([^\"]+)\"" % var, text)
            if value and value.group(1) not in found.setdefault(server, []):
                found[server].append(value.group(1))
    return {server: topics for server, topics in found.items() if topics}


def https(url):
    return url if isinstance(url, str) and url.startswith("https://") else ""


def webhook_summary(payload):
    alerts = payload.get("alerts") or []
    firing = payload.get("status") == "firing"
    names = sorted({a.get("labels", {}).get("alertname", "alert") for a in alerts})
    state = "firing" if firing else "resolved"
    title = "%s %s" % (names[0], state) if len(names) == 1 else "%d alerts %s" % (len(alerts), state)
    lines = [a.get("annotations", {}).get("summary") or a.get("labels", {}).get("instance", "") for a in alerts]
    body = "\n".join(l for l in lines[:5] if l)
    critical = firing and any(a.get("labels", {}).get("severity") == "critical" for a in alerts)
    click = next((https(a.get("generatorURL")) for a in alerts if https(a.get("generatorURL"))), "")
    return title, body, "critical" if critical else "normal", click


def group_key(payload):
    """Stable identity for one alert group across its firing and resolved posts."""
    key = payload.get("groupKey")
    if isinstance(key, str) and key:
        return key
    alerts = payload.get("alerts") or []
    return "|".join(sorted(
        "%s@%s" % (a.get("labels", {}).get("alertname", "alert"),
                   a.get("labels", {}).get("instance", ""))
        for a in alerts
    ))


def open_alerts_read():
    try:
        with open(OPEN_ALERTS) as fh:
            value = json.load(fh)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def open_alerts_write(value):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(OPEN_ALERTS + ".tmp", "w") as fh:
        json.dump(value, fh)
    os.replace(OPEN_ALERTS + ".tmp", OPEN_ALERTS)


def notification_close(notification_id):
    subprocess.run(
        ["gdbus", "call", "--session",
         "--dest", "org.freedesktop.Notifications",
         "--object-path", "/org/freedesktop/Notifications",
         "--method", "org.freedesktop.Notifications.CloseNotification",
         str(notification_id)],
        check=False, capture_output=True,
    )


def notify_send(app, glyph, urgency, title, body, click, replaces=0):
    """Post a notification and return its id, or 0 when the server gave none."""
    argv = ["notify-send", "-a", app, "-u", urgency, "-p",
            "-h", "string:omarchy-glyph:" + glyph]
    if replaces:
        argv += ["-r", str(replaces)]
    if click:
        argv += ["-h", "string:omarchy-exec-argv:" + json.dumps(["xdg-open", click])]
    argv += [title, html.escape(body, quote=False)]
    result = subprocess.run(argv, check=False, capture_output=True, text=True)
    try:
        return int(result.stdout.strip())
    except ValueError:
        return 0


def notify(msg):
    text = msg.get("message", "")
    try:
        payload = json.loads(text)
    except ValueError:
        payload = None

    if isinstance(payload, dict) and isinstance(payload.get("alerts"), list):
        title, body, urgency, click = webhook_summary(payload)
        app, glyph = "Homelab", "\U000f048d"
        # A firing critical alert is posted with no expiry on purpose — it must
        # not scroll away while nobody is looking. That is also why it never
        # left the screen: nothing ever took it down again. Alertmanager sends
        # a `resolved` post for the same group when the condition clears, so
        # that post is what closes the firing one. The resolved toast itself is
        # ordinary urgency and expires on its own.
        key = group_key(payload)
        opened = open_alerts_read()
        previous = opened.pop(key, 0)
        if payload.get("status") == "firing":
            # Replace rather than stack: a group that re-fires (a new alert
            # joins it, Alertmanager repeats it) should update the card that is
            # already up, not add another identical one.
            new_id = notify_send(app, glyph, urgency, title, body, click, replaces=previous)
            if new_id:
                opened[key] = new_id
        else:
            if previous:
                notification_close(previous)
            notify_send(app, glyph, "normal", title, body, click)
        open_alerts_write(opened)
        return

    priority = int(msg.get("priority") or 3)
    title = msg.get("title") or msg.get("topic", "ntfy")
    body = text
    urgency = "critical" if priority >= 5 else "low" if priority <= 2 else "normal"
    click = https(msg.get("click"))
    notify_send("ntfy", "\U000f009e", urgency, title, body, click)


def read_last_id():
    try:
        with open(LAST_ID) as fh:
            value = fh.read().strip()
        if time.time() - os.path.getmtime(LAST_ID) < MAX_REPLAY_S:
            return value
    except OSError:
        pass
    return ""


def write_last_id(value):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(LAST_ID + ".tmp", "w") as fh:
        fh.write(value)
    os.replace(LAST_ID + ".tmp", LAST_ID)


def subscribe(server, names, since):
    query = {"since": since} if since else {}
    url = "%s/%s/json" % (server, ",".join(urllib.parse.quote(n) for n in names))
    if query:
        url += "?" + urllib.parse.urlencode(query)
    # ntfy sends a keepalive every 45s, so a silent minute means a dead connection.
    # The edge WAF rejects urllib's default User-Agent.
    request = urllib.request.Request(url, headers={"User-Agent": "ntfy-notify"})
    with urllib.request.urlopen(request, timeout=90) as stream:
        for raw in stream:
            try:
                msg = json.loads(raw)
            except ValueError:
                continue
            if msg.get("event") != "message":
                # Keeps last-id fresh while connected, so a quiet hour is not mistaken for downtime.
                if os.path.exists(LAST_ID):
                    os.utime(LAST_ID)
                # A rotated topic in the homelab source reconnects on the next keepalive.
                if subscriptions().get(server) != names:
                    return
                continue
            if time.time() - int(msg.get("time", 0)) < MAX_REPLAY_S:
                notify(msg)
            write_last_id(msg.get("id", ""))


def main():
    delay = 2
    while True:
        started = time.time()
        try:
            subs = subscriptions()
            if not subs:
                print("ntfy-notify: no ntfy topics in %s" % HOMELAB_DIR, file=sys.stderr)
                time.sleep(300)
                continue
            # One stream; the homelab publishes to a single ntfy server.
            server, names = next(iter(subs.items()))
            subscribe(server, names, read_last_id())
        except Exception as exc:
            print("ntfy-notify: %s" % exc, file=sys.stderr)
        delay = 2 if time.time() - started > 120 else min(delay * 2, 60)
        time.sleep(delay)


if __name__ == "__main__":
    sys.exit(main())
