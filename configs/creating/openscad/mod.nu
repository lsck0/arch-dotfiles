use module.nu *

export const meta = {packages: {pacman: [openscad uv]}}

# MCP_FROZEN keeps a later fastmcp from slipping in under the pin; bump both together
const MCP_VERSION = "0.6.1"
const MCP_FROZEN = "2026-09-30"

export def link [cfg: record] {
    if (which openscad uvx | length) < 2 { return [] }
    let pkg = $"openscad-mcp==($MCP_VERSION)"
    [
        (ini-merge (xdg config OpenSCAD OpenSCAD.conf) {launcher: {showOnStartup: "false"}})
        (mcp-servers {openscad: {
            type: stdio, command: uvx, args: [--exclude-newer $MCP_FROZEN $pkg]
            env: {FASTMCP_CHECK_FOR_UPDATES: "off", FASTMCP_SHOW_SERVER_BANNER: "false", FASTMCP_TELEMETRY_MODE: "off"}
        }})
        (if (cache-stamp $pkg | path exists) { [] } else { step mcp-cache $pkg --network })
    ]
}

def cache-stamp [pkg: string]: nothing -> path {
    xdg cache dotfiles uvx $"($pkg)@($MCP_FROZEN)"
}

export def mcp-cache [pkg: string]: nothing -> nothing {
    ^uvx --exclude-newer $MCP_FROZEN --from $pkg python -c "import openscad_mcp"
    mkdir (cache-stamp $pkg | path dirname)
    touch (cache-stamp $pkg)
}
