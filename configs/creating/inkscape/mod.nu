use module.nu *

export const meta = {packages: {pacman: [inkscape]}}

# its deps resolve as of its release date; bump both together
const MCP_VERSION = "1.3.1"
const MCP_RELEASED = "2026-09-01"

export def link [cfg: record] {
    if (which inkscape uvx | length) < 2 { return [] }
    json-merge ($nu.home-dir | path join .claude.json) [
        (json-set [mcpServers inkscape-mcp] {
            type: stdio
            command: uvx
            args: [--exclude-newer $MCP_RELEASED --from $"inkscape-mcp==($MCP_VERSION)" inkscape-mcp --mode stdio]
            # fastmcp asks pypi for updates whenever it prints its banner, which this server always does
            env: {FASTMCP_CHECK_FOR_UPDATES: "off"}
        })
    ]
}
