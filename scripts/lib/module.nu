# a module's verbs return declarations built here; the engine applies the difference, nothing here writes

export use log.nu [log-info log-warn log-err log-debug]
export use profile.nu [profile-has profile-load]
export use platform.nu [platform-has display-xwayland-scale gpu-list]
export use json.nu [json-set json-delete]
export use secrets.nu [secret-is-plaintext secret-seed-guard]
use fetch.nu [fetch-file-done fetch-git-done]
use state.nu [nu-bin]
use ../../configs/core/wallust/palette.nu [palette-slots]

# every declaration has exactly these keys, so a plan, the state file and the UI read one shape
export const DECL_KEYS = [kind target source content mode generated edits state now argv creates then]
export const DECL_KINDS = [file link json ini unit exec step]
const MODE_FILE = "644"
const BIN_DIR = ".local/bin"
const DESKTOP_SYSTEM_DIR = "/usr/share/applications"
# an app rewriting a watched path in bursts would retrigger its hook in a loop
const HOOK_BRAKE = "StartLimitIntervalSec=1min\nStartLimitBurst=20\n"

def decl [kind: string, target: string, fields: record]: nothing -> record {
    {
        kind: $kind target: $target source: null content: null mode: $MODE_FILE generated: false edits: []
        state: null now: false argv: [] creates: null then: []
    } | merge $fields
}

def module-path [file: path]: nothing -> path {
    $file | path expand --no-symlink
}

export def unit-dir []: nothing -> path {
    if ($env.DOT_LAYER? | default user) == "system" {
        "/etc/systemd/system"
    } else {
        $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join systemd user
    }
}

# --then runs once the target changed: a restart, a reload, locale-gen
export def file-copy [src: path, dest: path, --mode: string = $MODE_FILE, --then: list<string> = []]: nothing -> record {
    decl file $dest {source: (module-path $src), mode: $mode, then: $then}
}

# generated output (a theme) is rewritten whenever it differs, never drift
export def file-text [dest: path, content: string, --mode: string = $MODE_FILE, --generated, --then: list<string> = []]: nothing -> record {
    decl file $dest {content: $content, mode: $mode, generated: $generated, then: $then}
}

export def file-render [src: path, dest: path, values: record, --mode: string = $MODE_FILE, --then: list<string> = []]: nothing -> record {
    let text = $values | items {|key, value| {key: $key, value: $value} }
        | reduce --fold (open --raw $src) {|pair, acc| $acc | str replace --all $"@($pair.key)@" ($pair.value | into string) }
    decl file $dest {content: $text, mode: $mode, then: $then}
}

export def files-into [dir: path, ...srcs: path]: nothing -> list<record> {
    $srcs | each {|src| file-copy $src ($dir | path join ($src | path basename)) }
}

export def file-link [src: path, dest: path]: nothing -> record {
    decl link $dest {source: (module-path $src)}
}

export def link-commands [...files: path]: nothing -> list<record> {
    $files | each {|file| file-link $file ($nu.home-dir | path join $BIN_DIR ($file | path parse | get stem)) }
}

export def json-merge [file: path, edits: list<record>, --then: list<string> = []]: nothing -> record {
    decl json $file {edits: $edits, then: $then}
}

# ini-merge <file> {section: {key: value}}: forces only these keys ("" is the part before any section); --missing-only
# seeds a key only where it is absent
export def ini-merge [file: path, values: record, --missing-only, --then: list<string> = []]: nothing -> record {
    decl ini $file {edits: [{values: $values, missing_only: $missing_only}], then: $then}
}

export def unit-file [src: path, --enable, --now, --then: list<string> = []]: nothing -> list<record> {
    let name = $src | path basename
    [(file-copy $src (unit-dir | path join $name) --then $then)] ++ (if $enable { [(unit-enable $name --now=$now)] } else { [] })
}

export def unit-enable [name: string, --now]: nothing -> record {
    decl unit $name {state: enabled, now: $now}
}

export def unit-disable [name: string, --now]: nothing -> record {
    decl unit $name {state: disabled, now: $now}
}

export def unit-mask [name: string]: nothing -> record {
    decl unit $name {state: masked}
}

export def dropin [unit: string, src: path, --name: string, --then: list<string> = []]: nothing -> record {
    file-copy $src (unit-dir | path join $"($unit).d" ($name | default ($src | path basename))) --then $then
}

export def desktop-override [id: string, edit: closure]: nothing -> list<record> {
    let system = $DESKTOP_SYSTEM_DIR | path join $id
    if not ($system | path exists) {
        return []
    }
    let dest = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join applications $id
    [(file-text $dest (open --raw $system | do $edit))]
}

# an imperative step the declarations cannot express; runs when the module applies, skipped once <creates> exists
export def exec [name: string, argv: list<string>, --creates: path]: nothing -> record {
    decl exec $name {argv: $argv, creates: $creates}
}

# step <command> [args]: one of the module's own exported commands, run at apply time (as root in the system layer)
# for logic that must read and edit live state
export def step [command: string, ...args: string]: nothing -> record {
    decl step $command {argv: $args}
}

def --wrapped dot [...args: string]: nothing -> list<string> {
    [(nu-bin) --no-config-file ($env.DOTFILES | path join scripts dot.nu)] ++ $args
}

# fetch-file <url> <sha256> <dest>: downloaded (resumably), verified, put in place; --extract <member> or . (all)
export def fetch-file [url: string, sha256: string, dest: path, --mode: string = $MODE_FILE, --extract: string]: nothing -> list<record> {
    if (fetch-file-done $sha256 $dest) { return [] }
    let extract = if $extract == null { [] } else { [--extract $extract] }
    [(exec $"fetch ($dest)" (dot fetch file $url $sha256 $dest --mode $mode ...$extract))]
}

export def fetch-git [url: string, commit: string, dir: path]: nothing -> list<record> {
    if (fetch-git-done $commit $dir) { return [] }
    [(exec $"fetch ($dir) at ($commit | str substring 0..11)" (dot fetch git $url $commit $dir))]
}

# group-admins <group>: a system group every wheel member is in
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

# user-hook <name> <script> --watch [paths]: a path unit that runs <script> when a watched path changes, armed and run
# once when its units change; --permanent also runs it at login, --mkdir makes a missing watch dir. without --permanent the hook retires
# when the verb stops declaring it (return no hook once its work is done)
export def user-hook [name: string, script: path, --watch: list<string>, --permanent, --no-brake, --mkdir]: nothing -> list<record> {
    let dir = unit-dir
    let path_unit = [
        "[Unit]" $"Description=watch for the ($name) hook" "" "[Path]"
    ] ++ ($watch | each { $"PathChanged=($in)" }) ++ (if $mkdir { ["MakeDirectory=yes"] } else { [] }) ++ ["" "[Install]" "WantedBy=default.target"]
    let install = if $permanent { "\n[Install]\nWantedBy=default.target\n" } else { "" }
    let service = $"[Unit]\nDescription=run the ($name) hook\n(if $no_brake { '' } else { $HOOK_BRAKE })\n[Service]\nType=oneshot\nExecStart=(module-path $script)\n($install)"
    [
        (file-text ($dir | path join $"($name).path") $"($path_unit | str join "\n")\n")
        # started once whenever its units changed; the path unit runs it from then on
        (file-text ($dir | path join $"($name).service") $service --then [systemctl --user start --no-block $"($name).service"])
        (unit-enable $"($name).path" --now)
    ] ++ (if $permanent { [(unit-enable $"($name).service")] } else { [] })
}

const PALETTE_SLOTS = [bg fg c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 light bg_conditioned]

export def palette-load []: nothing -> any {
    if not ($nu.home-dir | path join .cache wal colors.json | path exists) {
        return null
    }
    $PALETTE_SLOTS | zip (palette-slots) | reduce --fold {} {|p, acc| $acc | insert $p.0 $p.1 }
}

export def decls-flatten []: any -> list<record> {
    let value = $in
    let nested = {|v| ($v | describe) =~ '^(list|table)' }
    if $value == null { return [] }
    if not (do $nested $value) { return [$value] }
    $value | reduce --fold [] {|d, acc| $acc ++ (if (do $nested $d) { $d } else { [$d] }) }
}
