use module.nu *

export const meta = {packages: {pacman: [openscad uv]}}

# MCP_FROZEN cuts off its deps (mcp-uvx); bump both together
const MCP_VERSION = "0.6.1"
const MCP_FROZEN = "2026-09-30"

export def link [cfg: record] {
    if (which openscad | is-empty) { return [] }
    [
        (ini-merge (xdg config OpenSCAD OpenSCAD.conf) {launcher: {showOnStartup: "false"}})
        (mcp-uvx openscad $"openscad-mcp==($MCP_VERSION)" $MCP_FROZEN [openscad-mcp] openscad_mcp --env-vars {
            FASTMCP_CHECK_FOR_UPDATES: "off", FASTMCP_SHOW_SERVER_BANNER: "false", FASTMCP_TELEMETRY_MODE: "off"
        })
    ]
}
