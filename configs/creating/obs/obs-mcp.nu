#!/usr/bin/env -S nu --no-config-file
# obs-mcp with the websocket password read from obs's config at each start, so it never lands in ~/.claude.json

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib state.nu) [xdg]

def main []: nothing -> nothing {
    let bin = xdg data obs-mcp node_modules .bin obs-mcp
    if not ($bin | path exists) {
        print --stderr $"obs-mcp: ($bin) missing, rerun dot apply --user creating/obs \(it installs it with npm ci\)"
        exit 1
    }
    let ws_config = xdg config obs-studio plugin_config obs-websocket config.json
    if not ($ws_config | path exists) {
        print --stderr $"obs-mcp: ($ws_config) missing, rerun dot apply --user creating/obs"
        exit 1
    }
    let ws = open $ws_config
    $env.OBS_WEBSOCKET_PASSWORD = $ws.server_password? | default ""
    $env.OBS_WEBSOCKET_URL = $"ws://127.0.0.1:($ws.server_port)"
    exec $bin
}
