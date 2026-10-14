use module.nu *

export const meta = {packages: {pacman: [blender]}}

# bump the commit and constraints.txt (uv pip freeze of the tool env) together
# SECURITY: the add-on runs any python the server sends, unsandboxed, so the bridge never auto-starts
const MCP_URL = "https://projects.blender.org/lab/blender_mcp.git"
# v1.0.3
const MCP_COMMIT = "2cea8d566dde07fbac28a61d698909d69724e853"
const MCP_PORT = "9876"
const HERE = path self | path dirname

def src []: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join blender-mcp src
}

def pin []: nothing -> string {
    $"($MCP_COMMIT) (open --raw ($HERE | path join constraints.txt) | hash sha256)"
}

def pin-file []: nothing -> path {
    ^uv tool dir | str trim | path join blender-mcp .dotfiles-pin
}

export def link [cfg: record] {
    if (which blender uv | length) < 2 { return [] }
    let installed = try { open --raw (pin-file) | str trim } catch { "" }
    [
        (fetch-git $MCP_URL $MCP_COMMIT (src))
        # the server's deps held to constraints.txt, reinstalled only when the commit or the pins move
        (if $installed == (pin) { [] } else { step server-install })
        (step addon-install)
        (link-commands blender-mcp-bridge.nu)
        (desktop-override blender.desktop {
            let text = $in
            let bridge = $nu.home-dir | path join .local bin blender-mcp-bridge
            let action = $"\n[Desktop Action mcp-bridge]\nName=Blender with MCP bridge\nExec=($bridge) %f\n"
            let entry = $text | str replace --regex '(?m)^\[Desktop Entry\]$' "[Desktop Entry]\nActions=mcp-bridge;"
            $"($entry)($action)"
        })
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers blender-mcp] {
                type: stdio, command: (^uv tool dir --bin | str trim | path expand | path join blender-mcp), args: []
                env: {BLENDER_MCP_HOST: "127.0.0.1", BLENDER_MCP_PORT: $MCP_PORT}
            })
        ])
    ]
}

export def server-install []: nothing -> nothing {
    let pkg = $"blender-mcp @ git+($MCP_URL)@($MCP_COMMIT)#subdirectory=mcp"
    ^uv tool install -q --force --constraints ($HERE | path join constraints.txt) $pkg
    pin | save --force (pin-file)
}

# reinstalled when the installed copy differs from the pinned tree; mcp-prefs.py saves only on a change
export def addon-install []: nothing -> nothing {
    let addon = src | path join addon blender_mcp_addon
    let query = 'import bpy; print("EXT=" + bpy.utils.user_resource("EXTENSIONS"))'
    let probe = ^blender -b --factory-startup --python-expr $query | complete
    let extensions = $probe.stdout | lines | parse "EXT={dir}" | get --optional 0.dir
    if $extensions == null { error make {msg: "blender: no user extensions dir"} }
    let installed = $extensions | path join user_default mcp
    let same = (^diff -rq -x __pycache__ -x '.*' $addon $installed | complete).exit_code == 0
    if not $same {
        let tmp = mktemp --directory
        ^blender -c extension build --source-dir $addon --output-filepath ($tmp | path join mcp.zip) | ignore
        ^blender -c extension install-file -r user_default ($tmp | path join mcp.zip) | ignore
        rm --recursive $tmp
    }
    ^blender -b --python-exit-code 1 --python ($HERE | path join mcp-prefs.py) | ignore
}
