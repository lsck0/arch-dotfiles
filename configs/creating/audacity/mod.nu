use module.nu *

export const meta = {packages: {pacman: [audacity uv]}}

# MCP_FROZEN cuts off its deps (mcp-uvx); bump both together
const MCP_VERSION = "0.1.23"
const MCP_FROZEN = "2026-10-14"
const SCRIPT_PIPE = "/usr/lib/audacity/modules/mod-script-pipe.so"
# without prefs and app version audacity takes the config for a first run and resets it
const PREFS_VERSION = "1.1.1r1"

export def link [cfg: record] {
    if (which audacity | is-empty) or not ($SCRIPT_PIPE | path exists) { return [] }
    let built = ls $SCRIPT_PIPE | get 0.modified | format date "%Y-%m-%dT%H:%M:%S"
    let cfg_file = xdg config audacity audacity.cfg
    let version = package-version audacity | parse --regex '(?<Major>\d+)\.(?<Minor>\d+)\.(?<Micro>\d+)' | first
    [
        (ini-merge $cfg_file {"": {PrefsVersion: $PREFS_VERSION}, Version: $version} --missing-only)
        (ini-merge $cfg_file {
            GUI: {ShowSplashScreen: 0}
            Module: {mod-script-pipe: 1}
            ModulePath: {mod-script-pipe: $SCRIPT_PIPE}
            # the .so's mtime, so an upgrade re-enables the module
            ModuleDateTime: {mod-script-pipe: $built}
        })
        (mcp-uvx audacity $"audacity-mcp-server==($MCP_VERSION)" $MCP_FROZEN [audacity-mcp] audacity_mcp.tool_registry
            --env-vars {HF_HUB_DISABLE_TELEMETRY: "1"})
    ]
}
