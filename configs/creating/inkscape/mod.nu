use module.nu *

export const meta = {packages: {pacman: [inkscape uv]}}

# its deps resolve as of its release date; bump both together
const MCP_VERSION = "1.3.1"
const MCP_RELEASED = "2026-09-01"
# inkex pins lxml 5.4.0, which has no wheel for and fails to build on python 3.14; uv fetches this one
const MCP_PYTHON = "3.12"

export def link [cfg: record] {
    if (which inkscape uvx | length) < 2 { return [] }
    let pkg = $"inkscape-mcp==($MCP_VERSION)"
    [
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers inkscape-mcp] {
                type: stdio
                command: uvx
                args: [--python $MCP_PYTHON --exclude-newer $MCP_RELEASED --from $pkg inkscape-mcp --mode stdio]
                env: {FASTMCP_CHECK_FOR_UPDATES: "off"}
            })
        ])
        (if (cache-stamp $pkg | path exists) { [] } else { step mcp-cache $pkg })
    ]
}

def cache-stamp [pkg: string]: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join dotfiles uvx $"($pkg)@($MCP_RELEASED)-py($MCP_PYTHON)"
}

export def mcp-cache [pkg: string]: nothing -> nothing {
    ^uvx --python $MCP_PYTHON --exclude-newer $MCP_RELEASED --from $pkg python -c "import inkscape_mcp"
    mkdir (cache-stamp $pkg | path dirname)
    touch (cache-stamp $pkg)
}
