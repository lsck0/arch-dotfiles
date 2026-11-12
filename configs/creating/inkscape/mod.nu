use module.nu *

export const meta = {packages: {pacman: [fig2dev inkscape optipng uv]}}

# MCP_FROZEN cuts off its deps (mcp-uvx); bump both together
const MCP_VERSION = "1.3.1"
const MCP_FROZEN = "2026-09-01"
# inkex pins lxml 5.4.0, which has no wheel for and fails to build on python 3.14
const MCP_PYTHON = "3.12"
# inkscape merges its preferences over the built-in ones by group id, so this group alone is a complete file
const START_SCREEN_OFF = '<group id="boot" enabled="0" />'

def start-screen-set [file: path]: nothing -> bool {
    ($file | path exists) and (open --raw $file) =~ 'id="boot"[^>]*\benabled='
}

export def link [cfg: record] {
    if (which inkscape | is-empty) { return [] }
    let preferences = xdg config inkscape preferences.xml
    [
        (step start-screen-off $preferences --done=(start-screen-set $preferences))
        (mcp-uvx inkscape-mcp $"inkscape-mcp==($MCP_VERSION)" $MCP_FROZEN [inkscape-mcp --mode stdio] inkscape_mcp
            --python $MCP_PYTHON --env-vars {FASTMCP_CHECK_FOR_UPDATES: "off"})
    ]
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
