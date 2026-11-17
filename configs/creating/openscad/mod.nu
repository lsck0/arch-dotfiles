use module.nu *

export const meta = {packages: {pacman: [openscad uv]}}

export const options = {
    mcp: {type: bool, default: true, doc: "Register openscad-mcp with the coding agents; off, no agent session starts its server", label: "MCP server"}
}

# MCP_FROZEN cuts off its deps (mcp-uvx); bump both together
const MCP_VERSION = "0.6.1"
const MCP_FROZEN = "2026-09-30"

export def link [cfg: record] {
    if (which openscad | is-empty) { return [] }
    [
        (ini-merge (xdg config OpenSCAD OpenSCAD.conf) {launcher: {showOnStartup: "false"}})
        (if $cfg.mcp {
            mcp-uvx openscad $"openscad-mcp==($MCP_VERSION)" $MCP_FROZEN [openscad-mcp] openscad_mcp --env-vars {
                FASTMCP_CHECK_FOR_UPDATES: "off", FASTMCP_SHOW_SERVER_BANNER: "false", FASTMCP_TELEMETRY_MODE: "off"
            }
        })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    if (which openscad | is-empty) { return [] }
    let light = (palette-load | get --optional light) == "1"
    # stock schemes from /usr/share/openscad/color-schemes; the editor paper is the scheme's, not the qt palette's
    [(ini-merge (xdg config OpenSCAD OpenSCAD.conf) {
        editor: {syntaxhighlight: (if $light { "For Light Background" } else { "For Dark Background" })}
        "3dview": {colorscheme: (if $light { "Tomorrow" } else { "Tomorrow Night" })}
    })]
}
