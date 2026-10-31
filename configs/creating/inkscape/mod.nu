use module.nu *

export const meta = {packages: {pacman: [fig2dev inkscape optipng uv]}}

# MCP_RELEASED freezes its deps at the release date; bump both together
const MCP_VERSION = "1.3.1"
const MCP_RELEASED = "2026-09-01"
# inkex pins lxml 5.4.0, which has no wheel for and fails to build on python 3.14
const MCP_PYTHON = "3.12"
# inkscape merges its preferences over the built-in ones by group id, so this group alone is a complete file
const START_SCREEN_OFF = '<group id="boot" enabled="0" />'

def start-screen-set [file: path]: nothing -> bool {
    ($file | path exists) and (open --raw $file) =~ 'id="boot"[^>]*\benabled='
}

export def link [cfg: record] {
    if (which inkscape uvx | length) < 2 { return [] }
    let pkg = $"inkscape-mcp==($MCP_VERSION)"
    let preferences = xdg config inkscape preferences.xml
    [
        (if (start-screen-set $preferences) { [] } else { step start-screen-off $preferences })
        (mcp-servers {inkscape-mcp: {
            type: stdio
            command: uvx
            args: [--python $MCP_PYTHON --exclude-newer $MCP_RELEASED --from $pkg inkscape-mcp --mode stdio]
            env: {FASTMCP_CHECK_FOR_UPDATES: "off"}
        }})
        (if (cache-stamp $pkg | path exists) { [] } else { step mcp-cache $pkg --network })
    ]
}

def cache-stamp [pkg: string]: nothing -> path {
    xdg cache dotfiles uvx $"($pkg)@($MCP_RELEASED)-py($MCP_PYTHON)"
}

export def mcp-cache [pkg: string]: nothing -> nothing {
    ^uvx --python $MCP_PYTHON --exclude-newer $MCP_RELEASED --from $pkg python -c "import inkscape_mcp"
    mkdir (cache-stamp $pkg | path dirname)
    touch (cache-stamp $pkg)
}

export def start-screen-off [file: path]: nothing -> nothing {
    if not ($file | path exists) {
        mkdir ($file | path dirname)
        $"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n<inkscape version=\"1\">\n  <group id=\"options\">\n    ($START_SCREEN_OFF)\n  </group>\n</inkscape>\n" | save $file
        return
    }
    let text = open --raw $file
    let edited = if $text =~ 'id="boot"' {
        $text | str replace --regex '(id="boot")' '$1 enabled="0"'
    } else {
        $text | str replace --regex '(</inkscape>\s*)$' $"  <group id=\"options\">\n    ($START_SCREEN_OFF)\n  </group>\n$1"
    }
    $edited | save --force $file
}
