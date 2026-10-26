use module.nu *

# cuda only for libcudart.so.13: arch's usd and opensubdiv link it undeclared
export const meta = {packages: {pacman: [blender cuda uv]}}

# the add-on runs any python the server sends, unsandboxed, so the bridge never auto-starts
const MCP_URL = "https://projects.blender.org/lab/blender_mcp.git"
# v1.0.3; bump with constraints.txt (uv pip freeze of the tool env)
const MCP_COMMIT = "2cea8d566dde07fbac28a61d698909d69724e853"
const MCP_PORT = "9876"
# apparmor's blender-mcp profile keeps the venv read-only, so python cannot write __pycache__ at runtime
const INSTALL_FLAGS = ["--compile-bytecode"]
const HERE = path self | path dirname

def src []: nothing -> path {
    xdg cache blender-mcp src
}

def pin []: nothing -> string {
    $"($MCP_COMMIT) (open --raw ($HERE | path join constraints.txt) | hash sha256) ($INSTALL_FLAGS | str join ' ')"
}

def pin-file []: nothing -> path {
    ^uv tool dir | str trim | path join blender-mcp .dotfiles-pin
}

export def link [cfg: record] {
    if (which blender uv | length) < 2 { return [] }
    let installed = try { open --raw (pin-file) | str trim } catch { "" }
    [
        (fetch-git $MCP_URL $MCP_COMMIT (src))
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
        (mcp-servers {blender-mcp: {
            type: stdio, command: (^uv tool dir --bin | str trim | path expand | path join blender-mcp), args: []
            env: {BLENDER_MCP_HOST: "127.0.0.1", BLENDER_MCP_PORT: $MCP_PORT}
        }})
    ]
}

export def server-install []: nothing -> nothing {
    let pkg = $"blender-mcp @ git+($MCP_URL)@($MCP_COMMIT)#subdirectory=mcp"
    ^uv tool install -q --force ...$INSTALL_FLAGS --constraints ($HERE | path join constraints.txt) $pkg
    pin | save --force (pin-file)
}

def blender-run [args: list<string>]: nothing -> nothing {
    let run = ^blender ...$args | complete
    if $run.exit_code != 0 { error make {msg: $"blender ($args | first 3 | str join ' ') exited ($run.exit_code): ($run.stderr | lines | last 5 | str join "\n")"} }
}

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
        blender-run [-c extension build --source-dir $addon --output-filepath ($tmp | path join mcp.zip)]
        blender-run [-c extension install-file -r user_default ($tmp | path join mcp.zip)]
        rm --recursive $tmp
    }
    blender-run [-b --python-exit-code 1 --python ($HERE | path join mcp-prefs.py)]
}
