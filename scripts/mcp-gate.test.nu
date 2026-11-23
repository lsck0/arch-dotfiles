#!/usr/bin/env -S nu --no-config-file
use std/assert

const GATE = path self mcp-gate.py
const SERVER_WAIT = 5sec
# A streamable http server on an own loopback port, written to the file in argv[1]. The first session it hands out is
# one it no longer knows (an app restarted since), so the request after the handshake meets a 404; "slow" answers late.
const SERVER = '
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sessions = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        message = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        method = message.get("method")
        if method == "initialize":
            sessions.append(f"s{len(sessions) + 1}")
        elif self.headers.get("Mcp-Session-Id") != sessions[-1] or len(sessions) == 1:
            self.send_response(404)
            self.end_headers()
            return
        if "id" not in message:
            self.send_response(202)
            self.end_headers()
            return
        if method == "slow":
            time.sleep(1.5)
        body = json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": {"sessions": len(sessions)}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Mcp-Session-Id", sessions[-1])
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
open(sys.argv[1], "w").write(str(server.server_port))
server.serve_forever()
'

def request [id: int, method: string]: nothing -> string {
    {jsonrpc: "2.0", id: $id, method: $method} | to json --raw
}

def main [] {
    let work = mktemp --directory
    let port_file = $work | path join port
    let server = job spawn { ^python3 -c $SERVER $port_file }
    try {
        let deadline = (date now) + $SERVER_WAIT
        while not ($port_file | path exists) or (open --raw $port_file | is-empty) {
            assert ((date now) <= $deadline) "the test server never came up"
            sleep 50ms
        }
        let address = $"127.0.0.1:(open --raw $port_file)"
        let lines = [
            (request 1 initialize)
            ({jsonrpc: "2.0", method: "notifications/initialized"} | to json --raw)
            (request 2 slow)
            (request 3 ping)
        ]
        let run = $lines | str join "\n" | ^python3 $GATE --probe $address --app test --url $"http://($address)/mcp" | complete
        assert equal $run.exit_code 0 $"the relay failed: ($run.stderr | str trim)"
        let answers = $run.stdout | lines | each { from json }
        assert (not ($answers | any { $in.error? != null })) $"a request failed after the session was dropped: ($run.stdout | str trim)"
        assert equal ($answers.id | sort) [1 2 3] "answers for the wrong ids"
        # the dropped session was opened again, once, with the client's handshake
        assert equal ($answers | where id != 1 | get result.sessions | uniq) [2] $"sessions: ($run.stdout | str trim)"
        assert equal $answers.id [1 3 2] "ping waited behind the slow call"
    } catch {|e|
        job kill $server
        rm --recursive --force $work
        error make {msg: $e.msg}
    }
    job kill $server
    rm --recursive --force $work
}
