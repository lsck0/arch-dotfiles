use module.nu *

export const meta = {packages: {pacman: [openscad]}}

# openscad-mcp (github.com/RobertCoop/openscad-mcp): stdio over the openscad cli, no gui or listener; its deps frozen
# at a date so a later fastmcp never slips in under the pin, bump both together
const MCP_VERSION = "0.6.1"
const MCP_FROZEN = "2026-09-30"

export def link [cfg: record] {
    if (which openscad uvx | length) < 2 { return [] }
    let pkg = $"openscad-mcp==($MCP_VERSION)"
    [
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers openscad] {
                type: stdio, command: uvx, args: [--exclude-newer $MCP_FROZEN $pkg]
                # update checks against pypi and opentelemetry spans
                env: {
                    FASTMCP_CHECK_FOR_UPDATES: "off", FASTMCP_SHOW_SERVER_BANNER: "false", FASTMCP_TELEMETRY_MODE: "off"
                }
            })
        ])
        (if (cache-stamp $pkg | path exists) { [] } else { step mcp-cache $pkg })
    ]
}

def cache-stamp [pkg: string]: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join dotfiles uvx $"($pkg)@($MCP_FROZEN)"
}

export def mcp-cache [pkg: string]: nothing -> nothing {
    ^uvx --exclude-newer $MCP_FROZEN --from $pkg python -c "import openscad_mcp"
    mkdir (cache-stamp $pkg | path dirname)
    touch (cache-stamp $pkg)
}
