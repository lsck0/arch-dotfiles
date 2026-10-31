use module.nu *

export const meta = {packages: {pacman: [audacity uv]}}

# MCP_FROZEN freezes its deps at that date; bump both together
const MCP_VERSION = "0.1.23"
const MCP_FROZEN = "2026-10-14"
const SCRIPT_PIPE = "/usr/lib/audacity/modules/mod-script-pipe.so"
# without prefs and app version audacity takes the config for a first run and resets it
const PREFS_VERSION = "1.1.1r1"

export def link [cfg: record] {
    if (which audacity uvx | length) < 2 or not ($SCRIPT_PIPE | path exists) { return [] }
    let pkg = $"audacity-mcp-server==($MCP_VERSION)"
    let built = ls $SCRIPT_PIPE | get 0.modified | format date "%Y-%m-%dT%H:%M:%S"
    let cfg_file = xdg config audacity audacity.cfg
    let version = ^pacman -Q audacity | parse --regex '(?<Major>\d+)\.(?<Minor>\d+)\.(?<Micro>\d+)' | first
    [
        (ini-merge $cfg_file {"": {PrefsVersion: $PREFS_VERSION}, Version: $version} --missing-only)
        (ini-merge $cfg_file {
            GUI: {ShowSplashScreen: 0}
            Module: {mod-script-pipe: 1}
            ModulePath: {mod-script-pipe: $SCRIPT_PIPE}
            # the .so's mtime, so an upgrade re-enables the module
            ModuleDateTime: {mod-script-pipe: $built}
        })
        (mcp-servers {audacity: {
            type: stdio, command: uvx, args: [--exclude-newer $MCP_FROZEN --from $pkg audacity-mcp]
            env: {HF_HUB_DISABLE_TELEMETRY: "1"}
        }})
        (if (cache-stamp $pkg | path exists) { [] } else { step mcp-cache $pkg --network })
    ]
}

def cache-stamp [pkg: string]: nothing -> path {
    xdg cache dotfiles uvx $"($pkg)@($MCP_FROZEN)"
}

export def mcp-cache [pkg: string]: nothing -> nothing {
    ^uvx --exclude-newer $MCP_FROZEN --from $pkg python -c "import audacity_mcp.tool_registry"
    mkdir (cache-stamp $pkg | path dirname)
    touch (cache-stamp $pkg)
}
