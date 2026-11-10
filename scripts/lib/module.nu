# The module API: each declaration returns a record a mod.nu verb emits; converge.nu applies the difference.

export use log.nu [log-info log-note log-warn log-err log-debug]
export use profile.nu [profile-has profile-load]
export use platform.nu [platform-has display-xwayland-scale gpu-list]
export use json.nu [json-set json-delete]
export use secrets.nu [secret-is-plaintext secret-seed-guard owner-unlocked]
use fetch.nu [fetch-file-done fetch-file-cached fetch-git-done]
use state.nu [nu-bin LIB_DIR]
# what a module may read of the engine's state: its records and the root's state paths
export use state.nu [xdg recorded-hashes SYSTEM_STATE SYSTEM_REPO]
use ../../configs/core/wallust/palette.nu [palette-slots]

export const DECL_KEYS = [kind target source content mode generated inplace edits state now argv creates key done undo requires then network timeout]
export const DECL_KINDS = [file link json ini unit exec step]
const MODE_FILE = "644"
const BIN_DIR = ".local/bin"
const DESKTOP_SYSTEM_DIR = "/usr/share/applications"
# an app rewriting a watched path in bursts would retrigger its hook in a loop
const HOOK_BRAKE = "StartLimitIntervalSec=1min\nStartLimitBurst=20\n"

def decl [kind: string, target: string, fields: record]: nothing -> record {
    {
        kind: $kind target: $target source: null content: null mode: $MODE_FILE generated: false inplace: false edits: []
        state: null now: false argv: [] creates: null key: null done: false undo: [] requires: null then: [] network: false timeout: null
    } | merge $fields
}

# The xwayland_scale option of a module this one reads (meta.reads: the compositor's), else the detected value.
export def xwayland-scale-for [cfg: record]: nothing -> int {
    $cfg.deps? | default {} | values | get --optional xwayland_scale | compact | get --optional 0
    | default (display-xwayland-scale ($env.FORM_FACTOR? | default ""))
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

# Copies src to dest as a managed file; --then runs once dest changed (a restart, a reload); --in-place as file-text.
export def file-copy [src: path, dest: path, --mode: string = $MODE_FILE, --in-place, --then: list<string> = []]: nothing -> record {
    decl file $dest {source: (module-path $src), mode: $mode, inplace: $in_place, then: $then}
}

# --generated is overwritten without a drift check whenever its module runs; --in-place keeps the inode for watchers.
export def file-text [dest: path, content: string, --mode: string = $MODE_FILE, --generated, --in-place, --then: list<string> = []]: nothing -> record {
    decl file $dest {content: $content, mode: $mode, generated: $generated, inplace: $in_place, then: $then}
}

# Writes src to dest with each @key@ replaced by its value.
export def file-render [src: path, dest: path, values: record, --mode: string = $MODE_FILE, --generated, --then: list<string> = []]: nothing -> record {
    let text = $values | items {|key, value| {key: $key, value: $value} }
        | reduce --fold (open --raw $src) {|pair, acc| $acc | str replace --all $"@($pair.key)@" ($pair.value | into string) }
    decl file $dest {content: $text, mode: $mode, generated: $generated, then: $then}
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

# The module's aliases and defs for its tools, aliases.nu and aliases.zsh as far as it has them, dropped in as
# <name>.nu into nushell's user autoload dir and <name>.zsh into the conf.d core/zsh's zshrc sources.
export def shell-aliases [name: string]: nothing -> list<record> {
    [[src dir]; [aliases.nu (xdg config nushell autoload)] [aliases.zsh (xdg config zsh conf.d)]]
    | where { $in.src | path exists }
    | each {|f| file-copy $f.src ($f.dir | path join $"($name).($f.src | path parse | get extension)") }
}

# Applies json-set/json-delete edits to a live JSON file, keeping every other key.
export def json-merge [file: path, edits: list<record>, --then: list<string> = []]: nothing -> record {
    decl json $file {edits: $edits, then: $then}
}

# Whether a process of this exact name runs: a theme or reload step only acts on a running app.
export def process-running [name: string]: nothing -> bool {
    (^pgrep -x $name | complete).exit_code == 0
}

# Sets whole keys in a desktop entry's text (the first Key= line each), for desktop-override's edit.
export def desktop-set [values: record]: string -> string {
    let text = $in
    $values | items {|key, value| {key: $key, value: $value} }
    | reduce --fold $text {|kv, t|
        let pattern = $kv.key | str replace --all --regex '[.^$*+?()\[\]{}|\\]' '\${0}'
        # a $ in the value is literal, not a capture reference
        $t | str replace --regex $"\(?m\)^($pattern)=.*$" $"($kv.key)=($kv.value | into string | str replace --all '$' '$$')"
    }
}

const MCP_GATE = path self ../mcp-gate.py

# A spec with a `gate: {probe: "host:port", app}` runs through scripts/mcp-gate.py: the server while the app listens, else
# a server with no tools that says to start it, so an agent session never shows it failed.
def mcp-gated [name: string]: any -> any {
    let spec = $in
    if $spec == null or $spec.gate? == null { return $spec }
    let head = [$MCP_GATE --probe $spec.gate.probe --app $spec.gate.app --name $name]
    let args = if $spec.type? == http {
        $head ++ [--url $spec.url] ++ ($spec.headers? | default {} | items {|k, v| [--header $"($k): ($v)"] } | flatten)
    } else {
        $head ++ [-- $spec.command] ++ ($spec.args? | default [])
    }
    {type: stdio, command: python3, args: $args} | merge (if $spec.env? == null { {} } else { {env: $spec.env} })
}

# A Claude Code server spec in another agent's form; null where that agent has no counterpart.
def mcp-form [agent: string]: any -> any {
    let spec = $in
    if $spec == null or $agent == claude { return $spec }
    # a headersHelper is a command Claude Code runs for its headers
    if $spec.headersHelper? != null { return null }
    let stdio = $spec.type? in [null stdio]
    match $agent {
        gemini => (if $stdio { $spec | reject --optional type } else { $spec })
        copilot => ($spec | upsert type (if $stdio { "local" } else { $spec.type }) | upsert tools ["*"])
        hermes => ($spec | reject --optional type)
    }
}

# Registers MCP servers with every coding agent, name -> spec in Claude Code's form ({type: stdio, command, args, env}
# or {type: http, url, headers}), optionally with a `gate` (mcp-gated); null drops the name. Claude Code reads ~/.claude.json, Gemini ~/.gemini/settings.json
# and Copilot ~/.copilot/mcp-config.json, each in its own form. Hermes rewrites its YAML config itself, so its form goes
# to ~/.hermes/mcp-servers.json, a dropped name kept as null, and programming/hermes sets that into each profile. A server
# with a headersHelper reaches Claude Code only.
export def mcp-servers [servers: record]: nothing -> list<record> {
    let home = $nu.home-dir
    [
        [agent file key];
        [claude ($home | path join .claude.json) [mcpServers]]
        [gemini ($home | path join .gemini settings.json) [mcpServers]]
        [copilot ($home | path join .copilot mcp-config.json) [mcpServers]]
        [hermes ($home | path join .hermes mcp-servers.json) []]
    ] | each {|t|
        let edits = $servers | items {|name, spec|
            let form = $spec | mcp-gated $name | mcp-form $t.agent
            if $form != null or $t.agent == hermes { json-set ($t.key | append $name) $form } else { json-delete ($t.key | append $name) }
        }
        # the specs may carry a token, and only Claude Code keeps its own file private
        json-merge $t.file $edits --then (if $t.agent == claude { [] } else { [chmod "600" $t.file] })
    }
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

# An imperative command. Given any of --creates, --key, --done or --undo it is recorded: it is skipped once --done
# holds, or once --creates exists and --key equals the key it last ran with (each where given), and when it is no
# longer declared its --undo argv runs (from the state dir, so it outlives the module's dir). --requires: a path an
# earlier action lands (a fetch, a download), checked when it would run, so without it this waits as pending;
# --network: it downloads, so offline or on a remote's outage it waits as pending for the next apply; --timeout: its
# bound when converge's STEP_TIMEOUT is too short for it; --then: run once it went through, as a file's.
export def exec [
    name: string, argv: list<string>, --creates: path, --key: string, --done, --undo: list<string> = [], --requires: path
    --network, --timeout: duration, --then: list<string> = []
]: nothing -> record {
    decl exec $name {
        argv: $argv, creates: $creates, key: $key, done: $done, undo: $undo, requires: $requires, network: $network
        timeout: $timeout, then: $then
    }
}

# Runs one of the module's own exported commands at apply time, for logic that edits live state; --creates, --key,
# --done, --undo, --requires, --network and --timeout as exec's.
export def step [
    command: string, ...args: string, --creates: path, --key: string, --done, --undo: list<string> = [], --requires: path
    --network, --timeout: duration
]: nothing -> record {
    decl step $command {
        argv: $args, creates: $creates, key: $key, done: $done, undo: $undo, requires: $requires, network: $network
        timeout: $timeout
    }
}

# A --then argv running one of the module's own exported commands, so a reaction (a reload with its own checks) is
# module code that runs only when a declaration changed; identical ones run once per module run.
export def then-step [command: string, ...args: string]: nothing -> list<string> {
    let call = [$command ...($args | each { to nuon })] | str join " "
    [(nu-bin) --no-config-file -I $LIB_DIR -c $"use ($env.PWD | to nuon) [($command)]; ($call)"]
}

def --wrapped internal [...args: string]: nothing -> list<string> {
    [(nu-bin) --no-config-file ($env.DOTFILES | path join scripts lib internal.nu)] ++ $args
}

# Downloads url to dest checked against sha256; --extract an archive member or . for all; --in-place as file-text.
export def fetch-file [url: string, sha256: string, dest: path, --mode: string = $MODE_FILE, --extract: string, --in-place]: nothing -> list<record> {
    if (fetch-file-done $sha256 $dest) { return [] }
    let extract = if $extract == null { [] } else { [--extract $extract] }
    let in_place = if $in_place { [--in-place] } else { [] }
    [(exec $"fetch ($dest)" (internal fetch file $url $sha256 $dest --mode $mode ...$extract ...$in_place) --network=(not (fetch-file-cached $sha256)))]
}

# Checks out url at a pinned commit into dir.
export def fetch-git [url: string, commit: string, dir: path]: nothing -> list<record> {
    if (fetch-git-done $commit $dir) { return [] }
    [(exec $"fetch ($dir) at ($commit | str substring 0..11)" (internal fetch git $url $commit $dir) --network)]
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
    if (layer-is-system) { error make {msg: $"user-hook ($name): a user-layer helper, its --then starts a user unit"} }
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
    if not (xdg cache wal colors.json | path exists) {
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
