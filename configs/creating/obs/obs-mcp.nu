#!/usr/bin/env -S nu --no-config-file
# obs-mcp with the websocket password read from obs's config at each start, so it never lands in ~/.claude.json

const WS_CONFIG = ".config/obs-studio/plugin_config/obs-websocket/config.json"
const WS_PORT_DEFAULT = 4455

def main []: nothing -> nothing {
    let data = $nu.home-dir | path join .local share
    let bin = $data | path join obs-mcp node_modules .bin obs-mcp
    if not ($bin | path exists) {
        print --stderr $"obs-mcp: ($bin) missing, rerun dot apply --user creating/obs \(it installs it with npm ci\)"
        exit 1
    }
    let ws_config = $nu.home-dir | path join $WS_CONFIG
    if not ($ws_config | path exists) {
        print --stderr $"obs-mcp: ($ws_config) missing, rerun dot apply --user creating/obs"
        exit 1
    }
    let ws = open $ws_config
    $env.OBS_WEBSOCKET_PASSWORD = $ws.server_password? | default ""
    $env.OBS_WEBSOCKET_URL = $"ws://127.0.0.1:($ws.server_port? | default $WS_PORT_DEFAULT)"
    exec $bin
}
