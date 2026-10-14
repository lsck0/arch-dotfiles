use module.nu *

export const meta = {packages: {pacman: [godot]}}

# bump with SERVER in godot-mcp.nu
const URL = "https://github.com/tomyud1/godot-mcp.git"
const COMMIT = "3037a5bfc522767d71e63773209a0e308c778e39"

export def link [cfg: record] {
    [
        (fetch-git $URL $COMMIT ($env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join godot-mcp))
        (link-commands godot-mcp.nu godot-mcp-addon.nu)
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers godot-mcp] {type: stdio, command: ($nu.home-dir | path join .local bin godot-mcp), args: [], env: {}})
        ])
    ]
}
