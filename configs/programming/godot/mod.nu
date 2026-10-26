use module.nu *

export const meta = {packages: {pacman: [godot]}}

# bump with SERVER in godot-mcp.nu
const URL = "https://github.com/tomyud1/godot-mcp.git"
const COMMIT = "3037a5bfc522767d71e63773209a0e308c778e39"

export def link [cfg: record] {
    [
        (fetch-git $URL $COMMIT (xdg data godot-mcp))
        (link-commands godot-mcp.nu godot-mcp-addon.nu)
        (mcp-servers {godot-mcp: {type: stdio, command: ($nu.home-dir | path join .local bin godot-mcp), args: [], env: {}}})
    ]
}
