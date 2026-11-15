use module.nu *

export const meta = {packages: {pacman: [godot npm rsync]}}

# bump with mcp/package.json's godot-mcp-server (then `npm install --package-lock-only` there): the bridge and the
# addon speak one release's protocol
const URL = "https://github.com/tomyud1/godot-mcp.git"
const COMMIT = "3037a5bfc522767d71e63773209a0e308c778e39"
# the editor's GDScript language server (network/language_server/remote_port's default): it listens while a project
# is open in the editor, the only time the addon can reach the bridge. The bridge's own 6505 says nothing, it is the
# bridge that listens there
const EDITOR_LSP = "127.0.0.1:6005"

export def link [cfg: record] {
    [
        (fetch-git $URL $COMMIT (xdg data godot-mcp))
        # the bridge and every dependency at the lock's hashes; none needs an install script
        (mcp-npm godot-mcp mcp (xdg data godot-mcp-server) --ignore-scripts)
        (link-commands godot-mcp-addon.nu)
        (mcp-command godot-mcp godot-mcp.nu --gate {probe: $EDITOR_LSP, app: "the Godot editor (a project open)"})
    ]
}
