# The module API: each declaration returns a record a mod.nu verb emits; converge.nu applies the difference.

export use log.nu [log-info log-note log-warn log-err log-debug]
export use profile.nu [profile-has profile-load]
export use platform.nu [platform-has display-xwayland-scale gpu-list]
export use json.nu [json-set json-delete]
export use secrets.nu [secret-is-plaintext secret-seed-guard owner-unlocked]
use fetch.nu [fetch-file-done fetch-git-done]
use state.nu [nu-bin]
use ../../configs/core/wallust/palette.nu [palette-slots]

export const DECL_KEYS = [kind target source content mode generated inplace edits state now argv creates then]
export const DECL_KINDS = [file link json ini unit exec step]
const MODE_FILE = "644"
const BIN_DIR = ".local/bin"
const DESKTOP_SYSTEM_DIR = "/usr/share/applications"
# an app rewriting a watched path in bursts would retrigger its hook in a loop
const HOOK_BRAKE = "StartLimitIntervalSec=1min\nStartLimitBurst=20\n"

def decl [kind: string, target: string, fields: record]: nothing -> record {
    {
        kind: $kind target: $target source: null content: null mode: $MODE_FILE generated: false inplace: false edits: []
        state: null now: false argv: [] creates: null then: []
    } | merge $fields
}

# Falls back to the detected value for an app without an option of its own.
export def xwayland-scale-for [cfg: record]: nothing -> int {
    $cfg.deps?."desktop/hyprland"?.xwayland_scale? | default (display-xwayland-scale ($env.FORM_FACTOR? | default ""))
}

def module-path [file: path]: nothing -> path {
    $file | path expand --no-symlink
}

def layer-is-system []: nothing -> bool {
    ($env.DOT_LAYER? | default user) == "system"
}

# The systemd unit dir of the running layer: /etc/systemd/system for the system layer, else the user's.
export def unit-dir []: nothing -> path {
    if (layer-is-system) {
        "/etc/systemd/system"
    } else {
        xdg config systemd user
    }
}

# Copies src to dest as a managed file; --then runs once dest changed (a restart, a reload).
export def file-copy [src: path, dest: path, --mode: string = $MODE_FILE, --then: list<string> = []]: nothing -> record {
    decl file $dest {source: (module-path $src), mode: $mode, then: $then}
}

# --generated rewrites every run without drift; --in-place keeps the inode for watchers.
export def file-text [dest: path, content: string, --mode: string = $MODE_FILE, --generated, --in-place, --then: list<string> = []]: nothing -> record {
    decl file $dest {content: $content, mode: $mode, generated: $generated, inplace: $in_place, then: $then}
}

# Writes src to dest with each @key@ replaced by its value.
export def file-render [src: path, dest: path, values: record, --mode: string = $MODE_FILE, --then: list<string> = []]: nothing -> record {
    let text = $values | items {|key, value| {key: $key, value: $value} }
        | reduce --fold (open --raw $src) {|pair, acc| $acc | str replace --all $"@($pair.key)@" ($pair.value | into string) }
    decl file $dest {content: $text, mode: $mode, then: $then}
}

# Copies each src into dir under its own name.
export def files-into [dir: path, ...srcs: path]: nothing -> list<record> {
    $srcs | each {|src| file-copy $src ($dir | path join ($src | path basename)) }
}

# Symlinks dest to src in the repo, for an app that must read the repo live.
export def file-link [src: path, dest: path]: nothing -> record {
    decl link $dest {source: (module-path $src)}
}

# Links each script into ~/.local/bin under its stem.
export def link-commands [...files: path]: nothing -> list<record> {
    $files | each {|file| file-link $file ($nu.home-dir | path join $BIN_DIR ($file | path parse | get stem)) }
}

# Applies json-set/json-delete edits to a live JSON file, keeping every other key.
export def json-merge [file: path, edits: list<record>, --then: list<string> = []]: nothing -> record {
    decl json $file {edits: $edits, then: $then}
}

# A path under an XDG base dir (config, data, cache, state), honoring XDG_*_HOME.
export def xdg [kind: string, ...parts: string]: nothing -> path {
    let base = match $kind {
        config => ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config))
        data => ($env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share))
        cache => ($env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache))
        state => ($env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state))
        _ => (error make {msg: $"xdg: no base dir '($kind)'"})
    }
    $base | path join ...$parts
}

# Whether a process of this exact name runs: a theme or reload step only acts on a running app.
export def process-running [name: string]: nothing -> bool {
    (^pgrep -x $name | complete).exit_code == 0
}

# Sets whole keys in a desktop entry's text (the first Key= line each), for desktop-override's edit.
export def desktop-set [values: record]: string -> string {
    let text = $in
    $values | items {|key, value| {key: $key, value: $value} }
    | reduce --fold $text {|kv, t| $t | str replace --regex $"\(?m\)^($kv.key)=.*$" $"($kv.key)=($kv.value)" }
}

# Registers MCP servers with the agents (~/.claude.json's mcpServers), name -> server spec; null drops the name.
export def mcp-servers [servers: record]: nothing -> record {
    json-merge ($nu.home-dir | path join .claude.json) ($servers | items {|name, spec|
        if $spec == null { json-delete [mcpServers $name] } else { json-set [mcpServers $name] $spec }
    })
}

# Forces only these keys ("" is the part before any section); --missing-only seeds absent keys only.
export def ini-merge [file: path, values: record, --missing-only, --then: list<string> = []]: nothing -> record {
    decl ini $file {edits: [{values: $values, missing_only: $missing_only}], then: $then}
}

# Installs a unit file into the layer's unit dir, optionally enabled.
export def unit-file [src: path, --enable, --now, --then: list<string> = []]: nothing -> list<record> {
    let name = $src | path basename
    [(file-copy $src (unit-dir | path join $name) --then $then)] ++ (if $enable { [(unit-enable $name --now=$now)] } else { [] })
}

# A --then command restarting a unit, skipped while the unit is not installed yet (a fresh install).
export def unit-restart [name: string, --reload]: nothing -> list<string> {
    let scope = if (layer-is-system) { "--system" } else { "--user" }
    let verb = if $reload { "reload-or-restart" } else { "restart" }
    [sh -c $"! systemctl ($scope) cat ($name) >/dev/null 2>&1 || systemctl ($scope) ($verb) ($name)"]
}

export def unit-enable [name: string, --now]: nothing -> record {
    decl unit $name {state: enabled, now: $now}
}

export def unit-disable [name: string, --now]: nothing -> record {
    decl unit $name {state: disabled, now: $now}
}

# Masks a unit; --now also stops it, else every later daemon-reload warns that it changed under it.
export def unit-mask [name: string, --now]: nothing -> record {
    decl unit $name {state: masked, now: $now}
}

# Copies src as a drop-in into <unit>.d, named --name or its basename.
export def dropin [unit: string, src: path, --name: string, --then: list<string> = []]: nothing -> record {
    file-copy $src (unit-dir | path join $"($unit).d" ($name | default ($src | path basename))) --then $then
}

# A user copy of a system .desktop entry passed through edit; nothing when the app is not installed.
export def desktop-override [id: string, edit: closure]: nothing -> list<record> {
    let system = $DESKTOP_SYSTEM_DIR | path join $id
    if not ($system | path exists) {
        return []
    }
    let dest = xdg data applications $id
    [(file-text $dest (open --raw $system | do $edit))]
}

# An imperative command, skipped once --creates exists.
export def exec [name: string, argv: list<string>, --creates: path]: nothing -> record {
    decl exec $name {argv: $argv, creates: $creates}
}

# Runs one of the module's own exported commands at apply time, for logic that edits live state.
export def step [command: string, ...args: string]: nothing -> record {
    decl step $command {argv: $args}
}

def --wrapped internal [...args: string]: nothing -> list<string> {
    [(nu-bin) --no-config-file ($env.DOTFILES | path join scripts lib internal.nu)] ++ $args
}

# Downloads url to dest checked against sha256; --extract names an archive member, or . for all.
export def fetch-file [url: string, sha256: string, dest: path, --mode: string = $MODE_FILE, --extract: string]: nothing -> list<record> {
    if (fetch-file-done $sha256 $dest) { return [] }
    let extract = if $extract == null { [] } else { [--extract $extract] }
    [(exec $"fetch ($dest)" (internal fetch file $url $sha256 $dest --mode $mode ...$extract))]
}

# Checks out url at a pinned commit into dir.
export def fetch-git [url: string, commit: string, dir: path]: nothing -> list<record> {
    if (fetch-git-done $commit $dir) { return [] }
    [(exec $"fetch ($dir) at ($commit | str substring 0..11)" (internal fetch git $url $commit $dir))]
}

# Creates a system group and puts every wheel member in it.
export def group-admins [group: string]: nothing -> list<record> {
    let groups = open /etc/group | lines | parse "{name}:{x}:{gid}:{members}"
    let wheel = $groups | where name == wheel | get --optional 0.members | default "" | split row "," | where $it != ""
    let have = $groups | where name == $group | get --optional 0
    let missing = $wheel | where {|m| $have == null or $m not-in ($have.members | split row ",") }
    (
        (if $have == null { [(exec $"groupadd ($group)" [groupadd -r $group])] } else { [] })
        ++ ($missing | each {|m| exec $"($group) gets ($m)" [gpasswd -a $m $group] })
    )
}

# Without --permanent it retires once undeclared.
export def user-hook [name: string, script: path, --watch: list<string>, --permanent, --no-brake, --mkdir]: nothing -> list<record> {
    let dir = unit-dir
    let path_unit = [
        "[Unit]" $"Description=watch for the ($name) hook" "" "[Path]"
    ] ++ ($watch | each { $"PathChanged=($in)" }) ++ (if $mkdir { ["MakeDirectory=yes"] } else { [] }) ++ ["" "[Install]" "WantedBy=default.target"]
    let install = if $permanent { "\n[Install]\nWantedBy=default.target\n" } else { "" }
    let service = $"[Unit]\nDescription=run the ($name) hook\n(if $no_brake { '' } else { $HOOK_BRAKE })\n[Service]\nType=oneshot\nExecStart=(module-path $script)\n($install)"
    [
        (file-text ($dir | path join $"($name).path") $"($path_unit | str join "\n")\n")
        (file-text ($dir | path join $"($name).service") $service --then [systemctl --user start --no-block $"($name).service"])
        (unit-enable $"($name).path" --now)
    ] ++ (if $permanent { [(unit-enable $"($name).service")] } else { [] })
}

const PALETTE_SLOTS = [bg fg c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 light bg_conditioned]

# The current wallust palette as a record of slots, or null before the first theme.
export def palette-load []: nothing -> any {
    if not ($nu.home-dir | path join .cache wal colors.json | path exists) {
        return null
    }
    $PALETTE_SLOTS | zip (palette-slots) | reduce --fold {} {|p, acc| $acc | insert $p.0 $p.1 }
}

# <dir>/<host>/<file>, so machines backing up into one repo never overwrite each other.
export def host-file [dir: path, ...file: string]: nothing -> path {
    $dir | path join (sys host | get hostname) ...$file
}

# What a restore reads: this machine's copy, else the shared seed <dir>/<file> a new machine starts from.
export def host-seed [dir: path, ...file: string]: nothing -> path {
    let own = host-file $dir ...$file
    if ($own | path exists) { $own } else { $dir | path join ...$file }
}

# Flattens a verb's output, nested lists of declarations or a single one, into one list.
export def decls-flatten []: any -> list<record> {
    let value = $in
    let nested = {|v| ($v | describe) =~ '^(list|table)' }
    if $value == null { return [] }
    if not (do $nested $value) { return [$value] }
    $value | reduce --fold [] {|d, acc| $acc ++ (if (do $nested $d) { $d } else { [$d] }) }
}
