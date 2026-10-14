#!/usr/bin/env -S nu --no-config-file
# claude's godot mcp bridge; it has no auth, so loopback.cjs keeps every listener on 127.0.0.1

# bump with COMMIT in mod.nu: the bridge and the addon speak one release's protocol
const SERVER = "godot-mcp-server@0.6.0"
const LOOPBACK = path self | path expand | path dirname | path join loopback.cjs

def main []: nothing -> nothing {
    $env.NODE_OPTIONS = [$"--require=($LOOPBACK)" $env.NODE_OPTIONS?] | compact --empty | str join " "
    # without --no-force the bridge sigterms whatever already listens on 6505
    exec npx -y $SERVER --no-force
}
