#!/usr/bin/env -S nu --no-config-file
# claude's godot mcp server (mod.nu): tomyud1's node bridge, stdio to claude and a websocket on 127.0.0.1:6505 that
# the editor addon (godot-mcp-addon, the same release) dials. the first instance is the primary and owns 6505 and
# 6506, later ones proxy through it. --no-force: without it the bridge sigterms whatever already listens on 6505.
# no auth anywhere, so loopback.cjs keeps every listener it opens on 127.0.0.1

# bump with COMMIT in mod.nu: the bridge and the addon speak one release's protocol
const SERVER = "godot-mcp-server@0.6.0"
const LOOPBACK = path self | path expand | path dirname | path join loopback.cjs

def main []: nothing -> nothing {
    $env.NODE_OPTIONS = [$"--require=($LOOPBACK)" $env.NODE_OPTIONS?] | compact --empty | str join " "
    exec npx -y $SERVER --no-force
}
