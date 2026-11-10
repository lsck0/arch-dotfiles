use module.nu *

# cuda only for libcudart.so.13: arch's usd and opensubdiv link it undeclared
export const meta = {packages: {pacman: [blender cuda uv]}}

# the add-on runs any python the server sends, unsandboxed, so the bridge never auto-starts
const MCP_URL = "https://projects.blender.org/lab/blender_mcp.git"
# v1.0.3; bump with constraints.txt (uv pip freeze of the tool env)
const MCP_COMMIT = "2cea8d566dde07fbac28a61d698909d69724e853"
const MCP_PORT = "9876"
const MCP_HOST = "127.0.0.1"
# apparmor's blender-mcp profile keeps the venv read-only, so python cannot write __pycache__ at runtime
const INSTALL_FLAGS = ["--compile-bytecode"]
const HERE = path self | path dirname
const OPENAL_NOISE = "[ALSOFT]"

def src []: nothing -> path {
    xdg cache blender-mcp src
}

def pin []: nothing -> string {
    $"($MCP_COMMIT) (open --raw ($HERE | path join constraints.txt) | hash sha256) ($INSTALL_FLAGS | str join ' ')"
}

def pin-file []: nothing -> path {
    ^uv tool dir | str trim | path join blender-mcp .dotfiles-pin
}

def addon-pin-file []: nothing -> path {
    xdg cache blender-mcp .addon-pin
}

# the add-on tree is fixed by MCP_COMMIT (what fetch-git lands); the prefs script writes MCP_HOST and MCP_PORT into
# blender's prefs, so those four are the whole input
def addon-pin []: nothing -> string {
    $"($MCP_COMMIT) (open --raw ($HERE | path join mcp-prefs.py) | hash sha256) ($MCP_HOST):($MCP_PORT)"
}

# the comfy_generate extension (the Generate sidebar over llm/comfyui's comfy-gen): its files are the whole input
const GENERATE = "comfy_generate"
const GENERATE_ADDON = "bl_ext.user_default.comfy_generate"

def generate-pin-file []: nothing -> path {
    xdg cache blender-mcp .generate-pin
}

def generate-pin []: nothing -> string {
    glob ($HERE | path join $GENERATE "*") | where ($it | path type) == file | sort | each { open --raw $in | hash sha256 }
    | str join " "
}

# The pin files the steps wrote before they were keyed; each step removes its own, so a reverted pin cannot match one.
def stamped [file: path, pin: string]: nothing -> bool {
    (try { open --raw $file | str trim }) == $pin
}

export def link [cfg: record] {
    if (which blender uv | length) < 2 { return [] }
    let pin = pin
    let addon_pin = addon-pin
    let generate_pin = generate-pin
    [
        (fetch-git $MCP_URL $MCP_COMMIT (src))
        (step server-install --network --key $pin --done=(stamped (pin-file) $pin)
            --undo [uv tool uninstall blender-mcp])
        # builds from the fetched tree: while the fetch is pending, so is the add-on
        (step addon-install --requires (addon-src) --key $addon_pin --done=(stamped (addon-pin-file) $addon_pin))
        (step generate-install --key $generate_pin --done=(stamped (generate-pin-file) $generate_pin))
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
            env: {BLENDER_MCP_HOST: $MCP_HOST, BLENDER_MCP_PORT: $MCP_PORT}
        }})
    ]
}

export def server-install []: nothing -> nothing {
    let pkg = $"blender-mcp @ git+($MCP_URL)@($MCP_COMMIT)#subdirectory=mcp"
    ^uv tool install -q --force ...$INSTALL_FLAGS --constraints ($HERE | path join constraints.txt) $pkg
    rm --force (pin-file)
}

def blender-run [args: list<string>]: nothing -> nothing {
    let run = ^blender ...$args | complete
    # blender -c reports its errors on stdout, while stderr carries openal's complaints about a missing sound server
    let said = $"($run.stdout)\n($run.stderr)" | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with $OPENAL_NOISE) }
    if $run.exit_code != 0 { error make {msg: $"blender ($args | first 3 | str join ' ') exited ($run.exit_code): ($said | last 5 | str join "\n")"} }
}

def addon-src []: nothing -> path {
    src | path join addon blender_mcp_addon
}

# Builds an extension from its source tree and installs it into the user_default repository, unless the same tree is in.
def extension-install [source: path, id: string]: nothing -> nothing {
    let query = 'import bpy; print("EXT=" + bpy.utils.user_resource("EXTENSIONS"))'
    let probe = ^blender -b --factory-startup --python-expr $query | complete
    let extensions = $probe.stdout | lines | parse "EXT={dir}" | get --optional 0.dir
    if $extensions == null { error make {msg: "blender: no user extensions dir"} }
    let installed = $extensions | path join user_default $id
    let same = (^diff -rq -x __pycache__ -x '.*' $source $installed | complete).exit_code == 0
    if $same { return }
    let tmp = mktemp --directory
    try {
        blender-run [-c extension build --source-dir $source --output-filepath ($tmp | path join $"($id).zip")]
        blender-run [-c extension install-file -r user_default ($tmp | path join $"($id).zip")]
        rm --recursive $tmp
    } catch {|e| rm --recursive --force $tmp; error make $e }
}

export def addon-install []: nothing -> nothing {
    extension-install (addon-src) mcp
    with-env {BLENDER_MCP_HOST: $MCP_HOST, BLENDER_MCP_PORT: $MCP_PORT} {
        blender-run [-b --python-exit-code 1 --python ($HERE | path join mcp-prefs.py)]
    }
    rm --force (addon-pin-file)
}

export def generate-install []: nothing -> nothing {
    extension-install ($HERE | path join $GENERATE) $GENERATE
    let enable = (
        "import addon_utils, bpy\n"
        + $"addon_utils.enable\('($GENERATE_ADDON)', default_set=True, persistent=True\)\n"
        + $"assert addon_utils.check\('($GENERATE_ADDON)'\)[1], 'comfy_generate would not enable'\n"
        + "bpy.context.preferences.is_dirty = True\nbpy.ops.wm.save_userpref()\n"
    )
    blender-run [-b --python-exit-code 1 --python-expr $enable]
    rm --force (generate-pin-file)
}
