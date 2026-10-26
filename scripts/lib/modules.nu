# Module discovery, ordering and evaluation, each batch in one child nu.

use log.nu *
use state.nu [LIB_DIR nu-bin SYSTEM_STATE]

const SELF = path self
const REPO = path self ../..

# the verbs the engine calls on a module, and the hooks it reads while loading; nothing else is dispatched by name
export const VERBS = [link system theme apply backup restore update]
export const HOOKS = [detect packages]
const MARKER = "mod.nu"
const ROOT_MODULES = [scripts skills]
export const SECRETS_GROUP = "secrets"
const SECRETS_DATA = ["secrets/keys/**" "secrets/state/**"]
const META_DEFAULT = {deps: [], packages: {pacman: [], native: [], flatpak: {}, nix: []}, serial: false}

# The first word of each non-comment line of a dependencies.txt, none for a missing file.
export def names-read [file: path]: nothing -> list<string> {
    if not ($file | path exists) { return [] }
    open --raw $file | lines | each { split row "#" | first | str trim | split row " " | first } | where $it != ""
}

def native-script [mods: list<record>, body: string]: nothing -> string {
    let uses = $mods | enumerate | each {|m| $"module m($m.index) { export use ($m.item.dir | to nuon) *; export const DOT_MODULE = true }\nuse m($m.index)" }
    $uses | append $body | str join "\n"
}

# A child's log lines are in the run log already; other stderr (a deprecation, print -e) becomes a warning.
def child-warnings [stderr: string]: nothing -> nothing {
    let tag = $"($env.LOG_TAG? | default dotfiles): "
    let lines = $stderr | lines | where ($it | str trim) != ""
    $lines | where ($it | str starts-with $tag) | each { print -e $in } | ignore
    let other = $lines | where not ($it | str starts-with $tag)
    if ($other | is-not-empty) { log-warn ($other | str join "\n") }
}

# Each module dir's consts and exported commands; a mod.nu that does not parse is logged and marked broken.
def native-read [dirs: list<path>]: nothing -> list<record> {
    if ($dirs | is-empty) { return [] }
    let mods = $dirs | each {|dir| {dir: $dir} }
    let reads = $mods | enumerate | each {|m|
        $"{dir: ($m.item.dir | to nuon), consts: \($m($m.index) | reject DOT_MODULE\), commands: \(scope modules | where name == m($m.index) | get 0.commands.name\)}"
    }
    let script = native-script $mods $"[($reads | str join ' ')] | to nuon | save --force $env.DOT_EVAL_OUT"
    let out_file = mktemp --tmpdir
    let found = with-env {DOT_EVAL_OUT: $out_file} { ^(nu-bin) --no-config-file -I $LIB_DIR -c $script | complete }
    child-warnings $found.stderr
    let read = if $found.exit_code == 0 { open --raw $out_file | from nuon } else { null }
    rm --force $out_file
    if $read != null { return $read }
    let broken = $dirs | each {|dir| {dir: $dir, check: (^(nu-bin) --no-config-file -I $LIB_DIR -c $"use ($dir | to nuon)" | complete)} }
        | where check.exit_code != 0
    if ($broken | is-empty) { error make {msg: $"reading the modules failed: ($found.stderr)"} }
    $broken | each {|b|
        log-debug ($b.check.stderr | str trim)
        log-err $"($b.dir | path relative-to $REPO)/mod.nu does not parse, left out: (error-brief $b.check.stderr --root $REPO)"
    } | ignore
    let rest = $dirs | where $it not-in $broken.dir
    (if ($rest | is-empty) { [] } else { native-read $rest }) ++ ($broken | each {|b| {dir: $b.dir, consts: {}, commands: [], broken: true} })
}

def modules-scan [repo: path, markers: list<path>]: nothing -> table {
    let natives = native-read ($markers | where ($it | path basename) == "mod.nu" | path dirname)
    $markers | path dirname | uniq | sort | each {|dir|
        let rel = $dir | path relative-to $repo
        let root = not ($rel | str starts-with "configs/")
        let id = if $root { $rel } else { $rel | path relative-to configs }
        let group = if $root { "" } else { $id | path split | first }
        let native = $natives | where dir == $dir | get --optional 0 | default {consts: {}, commands: []}
        let meta = $META_DEFAULT | merge deep --strategy=append ($native.consts.meta? | default {})
        let sibling_deps = if $root { [] } else { names-read ($dir | path join dependencies.txt) | each {|d| $"($group)/($d)" } }
        {
            id: $id
            group: $group
            dir: $dir
            native: ($native.commands | where $it in ($VERBS ++ $HOOKS))
            verbs: ($native.commands | where $it in $VERBS)
            meta: ($meta | update deps { append $sibling_deps | uniq })
            options: ($native.consts.options? | default {})
            broken: ($native.broken? | default false)
        }
    }
}

# Every module in the repo, cached on the markers' stat; selected says whether this platform runs it.
export def modules-discover [repo: path, groups: list<string>]: nothing -> table {
    let configs = $repo | path join configs
    let markers = glob $"($configs)/*/**/($MARKER)" --exclude $SECRETS_DATA
        | append ($ROOT_MODULES | each {|r| glob $"($repo)/($r)/($MARKER)" } | flatten)
    let inputs = $markers | append (glob $"($configs)/**/dependencies.txt" --exclude $SECRETS_DATA)
        | append $SELF
    let key = ls --full-paths ...$inputs | select name size modified | to nuon | hash sha256
    # the caller's own cache, never root's: a user plans the system layer too
    let cache = if (is-admin) { $SYSTEM_STATE | path join discover.nuon } else { $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join dotfiles discover.nuon }
    let cached = try { open $cache } catch { {key: ""} }
    let found = if $cached.key == $key { $cached.modules } else {
        let scanned = modules-scan $repo $markers
        if not ($scanned | any { $in.broken }) {
            mkdir ($cache | path dirname)
            {key: $key, modules: $scanned} | save --force $cache
        }
        $scanned
    }
    $found | insert selected {|m| $m.group in ["" $SECRETS_GROUP] or $m.group in $groups or $m.id in $groups }
}

# The modules in run order, each with after (what it waits for) and level; ties break by sorted id.
export def modules-graph [repo: path, modules: table]: nothing -> table {
    let ids = $modules.id
    let groups = $modules.group | uniq | where $it != ""
    let group_deps = $groups | each {|g|
        let deps = if $g == $SECRETS_GROUP { $groups | where $it != $g } else {
            names-read ($repo | path join configs $g dependencies.txt) | append (if $g == "base" { [] } else { [base] })
        }
        {group: $g, deps: $deps}
    }
    let with_preds = $modules | each {|m|
        let by_group = if $m.group == "" {
            $modules | where group != "" | get id
        } else {
            let deps = $group_deps | where group == $m.group | get 0.deps
            $modules | where group in $deps | get id
        }
        $m | insert after ($by_group | append $m.meta.deps | where $it in $ids and $it != $m.id | uniq)
    }
    let sorted = $with_preds | sort-by id
    let position = $sorted | enumerate | reduce --fold {} {|r, acc| $acc | insert $r.item.id $r.index }
    let dependents = $sorted | each {|m| $m.after | each {|a| {after: $a, id: $m.id} } } | flatten | group-by after
    mut waiting = $sorted | reduce --fold {} {|m, acc| $acc | insert $m.id ($m.after | length) }
    mut ready = $sorted | where ($it.after | is-empty) | get id
    mut done = {}
    mut order = []
    while ($ready | is-not-empty) {
        let id = $ready | first
        $ready = $ready | skip 1
        let next = $sorted | get ($position | get $id)
        let finished = $done
        let level = $next.after | each {|a| $finished | get $a } | append (-1) | math max | $in + 1
        $done = $done | insert $id $level
        $order = $order | append ($next | insert level $level)
        mut freed = []
        for d in ($dependents | get --optional $id | default [] | get --optional id | default []) {
            let count = ($waiting | get $d) - 1
            $waiting = $waiting | upsert $d $count
            if $count == 0 { $freed = $freed | append $d }
        }
        if ($freed | is-not-empty) { $ready = $ready | append $freed | sort }
    }
    if ($order | length) != ($sorted | length) {
        let finished = $done
        error make {msg: $"dependency cycle among ($sorted | where id not-in ($finished | columns) | get id | str join ' ')"}
    }
    $order
}

# --private runs under umask 077, for a backup writing into configs/secrets/.
export def modules-eval [modules: table, verb: string, cfgs: record, args: list, --private]: nothing -> table {
    if ($modules | is-empty) { return [] }
    let calls = $modules | enumerate | each {|m|
        let name = $m.item.dir | path basename
        let cfg = $cfgs | get $m.item.id | to nuon
        $"{id: ($m.item.id | to nuon), run: {|| cd ($m.item.dir | to nuon); with-env {DOTFILES_MODULE: ($m.item.id | to nuon)} { m($m.index) ($verb) ($cfg) ($args | each { to nuon } | str join ' ') } }}"
    }
    let body = $"[($calls | str join ' ')] | each {|c| try { {id: $c.id, ok: true, decls: \(do $c.run | decls-flatten\), error: null} } catch {|e| {id: $c.id, ok: false, decls: [], error: $e.msg} } } | to nuon | save --force $env.DOT_EVAL_OUT"
    let run = [(nu-bin) --no-config-file -I $LIB_DIR -c (native-script ($modules | select dir) $"use module.nu *\n($body)")]
    let out_file = mktemp --tmpdir
    let out = with-env {DOT_EVAL_OUT: $out_file} {
        if $private { ^bash -c 'umask 077 && exec "$@"' private ...$run | complete } else { ^($run | first) ...($run | skip 1) | complete }
    }
    child-warnings $out.stderr
    let result = if $out.exit_code == 0 and ($out_file | path type) == "file" { open --raw $out_file | from nuon } else { null }
    rm --force $out_file
    if $result == null {
        error make {msg: $"evaluating ($verb) exited ($out.exit_code): ($out.stdout)($out.stderr)"}
    }
    $result
}

# The pacman, flatpak and nix packages every enabled module on this platform declares.
export def modules-packages [repo: path, modules: table, platform: record]: nothing -> record {
    let wsl = $platform.form_factor == "wsl"
    let selected = $modules | where {|m| $m.selected and $m.cfg.enable }
    let computing = $selected | where {|m| "packages" in $m.native }
    let results = modules-eval $computing packages ($computing | reduce --fold {} {|m, acc| $acc | insert $m.id $m.cfg }) []
    $results | where not ok | each { log-warn $"($in.id): packages failed: ($in.error)" } | ignore
    let computed = $results | reduce --fold {} {|r, acc| $acc | insert $r.id ($r.decls | get --optional 0 | default {}) }
    # a broken module or a failed packages hook declares too little: callers must not remove by this list
    let incomplete = ($results | where not ok | get id) ++ ($modules | where {|m| $m.selected and ($m.broken? | default false) } | get id)
    let on = $selected | each {|m| $m | update meta.packages {|x| $x.meta.packages | merge deep --strategy=append ($computed | get --optional $m.id | default {}) } }
    {
        pacman: ($on | each {|m| $m.meta.packages.pacman ++ (if $wsl { [] } else { $m.meta.packages.native }) } | flatten | append $platform.extra_packages | uniq | sort)
        flatpak: ($on | reduce --fold {} {|m, acc| $acc | merge $m.meta.packages.flatpak })
        nix: ($on | each { $in.meta.packages.nix } | flatten | uniq | sort)
        incomplete: $incomplete
    }
}
