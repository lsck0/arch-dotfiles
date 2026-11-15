use module.nu *

export const meta = {packages: {pacman: [godot npm rsync]}}

# bump with mcp/package.json's godot-mcp-server (then `npm install --package-lock-only` there): the bridge and the
# addon speak one release's protocol
const URL = "https://github.com/tomyud1/godot-mcp.git"
const COMMIT = "3037a5bfc522767d71e63773209a0e308c778e39"
const LOCK_KEY_LENGTH = 16
# the editor's GDScript language server (network/language_server/remote_port's default): it listens while a project
# is open in the editor, the only time the addon can reach the bridge. The bridge's own 6505 says nothing, it is the
# bridge that listens there
const EDITOR_LSP = "127.0.0.1:6005"

export def link [cfg: record] {
    let prefix = xdg data godot-mcp-server
    let node_modules = $prefix | path join node_modules
    let lock_hash = open --raw mcp/package-lock.json | hash sha256 | str substring 0..<($LOCK_KEY_LENGTH)
    [
        (fetch-git $URL $COMMIT (xdg data godot-mcp))
        (file-copy mcp/package.json ($prefix | path join package.json))
        (file-copy mcp/package-lock.json ($prefix | path join package-lock.json))
        # the bridge and every dependency at the lock's hashes; none needs an install script
        (exec godot-mcp-install [npm ci --ignore-scripts --no-audit --no-fund --prefix $prefix] --creates $node_modules
            --key $lock_hash --undo [rm -rf $node_modules] --network)
        (link-commands godot-mcp.nu godot-mcp-addon.nu)
        (mcp-servers {godot-mcp: {
            type: stdio, command: ($nu.home-dir | path join .local bin godot-mcp), args: []
            gate: {probe: $EDITOR_LSP, app: "the Godot editor (a project open)"}
        }})
    ]
}
