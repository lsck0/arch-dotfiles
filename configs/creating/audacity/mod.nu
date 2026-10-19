use module.nu *

export const meta = {packages: {pacman: [audacity]}}

# deps frozen at a date; bump both together
const MCP_VERSION = "0.1.23"
const MCP_FROZEN = "2026-10-14"
const SCRIPT_PIPE = "/usr/lib/audacity/modules/mod-script-pipe.so"

export def link [cfg: record] {
    if (which audacity uvx | length) < 2 or not ($SCRIPT_PIPE | path exists) { return [] }
    let pkg = $"audacity-mcp-server==($MCP_VERSION)"
    let built = ls $SCRIPT_PIPE | get 0.modified | format date "%Y-%m-%dT%H:%M:%S"
    [
        # the path and the .so's mtime, so an upgrade re-enables it; audacity rewrites the file on exit
        (ini-merge ($nu.home-dir | path join .config audacity audacity.cfg) {
            Module: {mod-script-pipe: 1}
            ModulePath: {mod-script-pipe: $SCRIPT_PIPE}
            ModuleDateTime: {mod-script-pipe: $built}
        })
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers audacity] {
                type: stdio, command: uvx, args: [--exclude-newer $MCP_FROZEN --from $pkg audacity-mcp]
                env: {HF_HUB_DISABLE_TELEMETRY: "1"}
            })
        ])
        (if (cache-stamp $pkg | path exists) { [] } else { step mcp-cache $pkg })
    ]
}

def cache-stamp [pkg: string]: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join dotfiles uvx $"($pkg)@($MCP_FROZEN)"
}

export def mcp-cache [pkg: string]: nothing -> nothing {
    ^uvx --exclude-newer $MCP_FROZEN --from $pkg python -c "import audacity_mcp.tool_registry"
    mkdir (cache-stamp $pkg | path dirname)
    touch (cache-stamp $pkg)
}
