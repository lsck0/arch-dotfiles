#!/usr/bin/env -S nu --no-config-file
# claude's godot mcp bridge; it has no auth, so loopback.cjs keeps every listener on 127.0.0.1

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib state.nu) [xdg]

const LOOPBACK = path self | path expand | path dirname | path join loopback.cjs

def main []: nothing -> nothing {
    let bin = xdg data godot-mcp-server node_modules .bin godot-mcp-server
    if not ($bin | path exists) {
        print --stderr $"godot-mcp: ($bin) missing, rerun dot apply --user programming/godot \(it installs it with npm ci\)"
        exit 1
    }
    $env.NODE_OPTIONS = [$"--require=($LOOPBACK)" $env.NODE_OPTIONS?] | compact --empty | str join " "
    # without --no-force the bridge sigterms whatever already listens on 6505
    exec $bin --no-force
}
