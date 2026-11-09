#!/usr/bin/env python3
"""An MCP server that bridges to an app only while the app runs (scripts/lib/module.nu mcp-servers, a spec's `gate`).

mcp-gate.py --probe HOST:PORT --app NAME [--url URL [--header 'K: V']...] [-- COMMAND ARGS...]

At start it probes the app's port. Up: a command is exec'd in place (a stdio server), a url is relayed (stdio to
streamable http). Down: it answers the handshake itself with no tools and an instruction to start the app, so an agent
session shows no failed server; reconnecting the server (/mcp) after starting the app picks the bridge up.
"""

import argparse
import json
import os
import socket
import sys
import urllib.error
import urllib.request

PROBE_TIMEOUT_S = 0.5
HTTP_TIMEOUT_S = 600
METHOD_NOT_FOUND = -32601


def up(probe: str) -> bool:
    host, _, port = probe.rpartition(":")
    try:
        with socket.create_connection((host, int(port)), timeout=PROBE_TIMEOUT_S):
            return True
    except OSError:
        return False


def send(message: dict) -> None:
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def offline(app: str, name: str) -> None:
    note = f"{app} is not running, so this server has no tools. Start {app}, then reconnect this MCP server."
    empty = {
        "tools/list": {"tools": []},
        "resources/list": {"resources": []},
        "prompts/list": {"prompts": []},
        "ping": {},
    }
    for line in sys.stdin:
        try:
            request = json.loads(line)
        except ValueError:
            continue
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
            send({"jsonrpc": "2.0", "id": request["id"], "result": result})
        elif method in empty:
            send({"jsonrpc": "2.0", "id": request["id"], "result": empty[method]})
        else:
            send({"jsonrpc": "2.0", "id": request["id"], "error": {"code": METHOD_NOT_FOUND, "message": note}})


def relay(url: str, headers: list[str]) -> None:
    base = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    for header in headers:
        key, _, value = header.partition(":")
        base[key.strip()] = value.strip()
    session = None
    for line in sys.stdin:
        if not line.strip():
            continue
        request = urllib.request.Request(
            url, data=line.encode(), method="POST", headers=base | ({"Mcp-Session-Id": session} if session else {})
        )
        try:
            with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_S) as response:
                session = response.headers.get("Mcp-Session-Id", session)
                kind = response.headers.get("Content-Type", "")
                if response.status == 202:
                    continue
                if kind.startswith("text/event-stream"):
                    for raw in response:
                        text = raw.decode().rstrip("\r\n")
                        if text.startswith("data:") and text[5:].strip():
                            sys.stdout.write(text[5:].strip() + "\n")
                            sys.stdout.flush()
                else:
                    body = response.read().decode().strip()
                    if body:
                        sys.stdout.write(body + "\n")
                        sys.stdout.flush()
        except (urllib.error.URLError, OSError) as error:
            message = json.loads(line)
            if "id" in message:
                send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32000, "message": f"relay: {error}"}})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--name", default="gated")
    parser.add_argument("--url")
    parser.add_argument("--header", action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not up(args.probe):
        offline(args.app, args.name)
    elif args.url:
        relay(args.url, args.header)
    elif command:
        os.execvp(command[0], command)
    else:
        sys.exit("mcp-gate: neither --url nor a command")


if __name__ == "__main__":
    main()
