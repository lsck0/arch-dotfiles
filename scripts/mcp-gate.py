#!/usr/bin/env python3
"""An MCP server that bridges to an app only while the app runs (scripts/lib/module.nu mcp-servers, a spec's `gate`).

mcp-gate.py --probe HOST:PORT --app NAME [--url URL] [-- COMMAND ARGS...]

A url's headers come as a json object in MCP_GATE_HEADERS, never argv: any local user reads a process's argv, only its
owner its environment.

At start it probes the app's port. Up: a command is exec'd in place (a stdio server), a url is relayed (stdio to
streamable http, each request on its own thread so a long tool call holds up nothing behind it; a session the app
dropped, as on its restart, is opened again with the client's own handshake). Down: it answers the handshake itself with no tools and an instruction to start the app, so an agent
session shows no failed server; reconnecting the server (/mcp) after starting the app picks the bridge up.
"""

import argparse
import http.client
import json
import os
import socket
import sys
import threading
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PROBE_TIMEOUT_S = 0.5
HTTP_TIMEOUT_S = 600
REQUESTS_PARALLEL_MAX = 8
METHOD_NOT_FOUND = -32601
RELAY_FAILED = -32000
# streamable http: 404 is a session the server no longer knows, 400 one it does not accept
SESSION_GONE = (400, 404)
HANDSHAKE = ("initialize", "notifications/initialized")

stdout_lock = threading.Lock()


def up(probe: str) -> bool:
    host, _, port = probe.rpartition(":")
    try:
        with socket.create_connection((host, int(port)), timeout=PROBE_TIMEOUT_S):
            return True
    except OSError:
        return False


def emit(text: str) -> None:
    with stdout_lock:
        sys.stdout.write(text + "\n")
        sys.stdout.flush()


def reply(request_id, **body) -> None:
    emit(json.dumps({"jsonrpc": "2.0", "id": request_id} | body))


def parse(line: str) -> dict:
    try:
        message = json.loads(line)
    except ValueError:
        return {}
    return message if isinstance(message, dict) else {}


def offline(app: str, name: str) -> None:
    note = f"{app} is not running, so this server has no tools. Start {app}, then reconnect this MCP server."
    empty = {
        "tools/list": {"tools": []},
        "resources/list": {"resources": []},
        "prompts/list": {"prompts": []},
        "ping": {},
    }
    for line in sys.stdin:
        request = parse(line)
        if "id" not in request:
            continue
        method = request.get("method", "")
        if method == "initialize":
            version = request.get("params", {}).get("protocolVersion", "2025-03-26")
            result = {
                "protocolVersion": version,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": name, "version": "offline"},
                "instructions": note,
            }
            reply(request["id"], result=result)
        elif method in empty:
            reply(request["id"], result=empty[method])
        else:
            reply(request["id"], error={"code": METHOD_NOT_FOUND, "message": note})


def relay(url: str, headers: dict[str, str]) -> None:
    base = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"} | headers
    state = {"session": None}
    handshake = []
    renewing = threading.Lock()

    def post(line: str, quiet: bool = False) -> None:
        session = state["session"]
        request = urllib.request.Request(
            url, data=line.encode(), method="POST", headers=base | ({"Mcp-Session-Id": session} if session else {})
        )
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_S) as response:
            state["session"] = response.headers.get("Mcp-Session-Id", state["session"])
            if response.status == 202:
                return
            if response.headers.get("Content-Type", "").startswith("text/event-stream"):
                for raw in response:
                    text = raw.decode().rstrip("\r\n")
                    if text.startswith("data:") and text[5:].strip() and not quiet:
                        emit(text[5:].strip())
            else:
                body = response.read().decode().strip()
                if body and not quiet:
                    emit(body)

    def renew(stale: str) -> None:
        with renewing:
            # another request already opened the new session
            if state["session"] != stale:
                return
            state["session"] = None
            try:
                for line in handshake:
                    post(line, quiet=True)
            except Exception:
                # keep the stale id, so the next request finds the session gone again and retries the handshake
                state["session"] = stale
                raise

    def forward(line: str) -> None:
        stale = state["session"]
        try:
            try:
                post(line)
            except urllib.error.HTTPError as error:
                if stale is None or error.code not in SESSION_GONE:
                    raise
                renew(stale)
                post(line)
        except (urllib.error.URLError, OSError, http.client.HTTPException, ValueError) as error:
            message = parse(line)
            if "id" in message:
                reply(message["id"], error={"code": RELAY_FAILED, "message": f"relay: {error}"})

    with ThreadPoolExecutor(REQUESTS_PARALLEL_MAX) as pool:
        for line in sys.stdin:
            if not line.strip():
                continue
            if parse(line).get("method") in HANDSHAKE:
                # in order and before anything else: every later request carries the session it opens
                handshake.append(line)
                forward(line)
            else:
                pool.submit(forward, line)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--name", default="gated")
    parser.add_argument("--url")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not up(args.probe):
        offline(args.app, args.name)
    elif args.url:
        relay(args.url, json.loads(os.environ.pop("MCP_GATE_HEADERS", "{}")))
    elif command:
        os.execvp(command[0], command)
    else:
        sys.exit("mcp-gate: neither --url nor a command")


if __name__ == "__main__":
    main()
