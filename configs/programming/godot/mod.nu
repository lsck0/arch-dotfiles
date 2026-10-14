use module.nu *

export const meta = {packages: {pacman: [godot]}}

# the editor addon from one pinned checkout of tomyud1/godot-mcp (v0.6.0), never upstream's head; bump with
# SERVER in godot-mcp.nu. per project, so godot-mcp-addon copies it into one on demand
const URL = "https://github.com/tomyud1/godot-mcp.git"
const COMMIT = "3037a5bfc522767d71e63773209a0e308c778e39"

export def link [cfg: record] {
    [
        (fetch-git $URL $COMMIT ($env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join godot-mcp))
        # claude's bridge to a running editor with the addon enabled, and the command that puts the addon in a project
        (link-commands godot-mcp.nu godot-mcp-addon.nu)
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers godot-mcp] {type: stdio, command: ($nu.home-dir | path join .local bin godot-mcp), args: [], env: {}})
        ])
    ]
}
