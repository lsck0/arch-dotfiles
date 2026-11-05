# Module discovery, ordering and evaluation, each batch in one child nu.

use log.nu *
use state.nu [LIB_DIR nu-bin SYSTEM_STATE xdg]

const SELF = path self
const REPO = path self ../..

# the verbs the engine calls on a module, and the hooks it reads while loading; nothing else is dispatched by name
export const VERBS = [link system theme apply backup restore update]
export const HOOKS = [detect packages]
const MARKER = "mod.nu"
export const ROOT_MODULES = [scripts skills]
export const SECRETS_GROUP = "secrets"
export const SECRETS_DATA = ["secrets/keys/**" "secrets/state/**"]
const META_DEFAULT = {deps: [], packages: {pacman: [], native: [], flatpak: {}, nix: []}, serial: false}
# a verb or hook evaluated in a child nu is killed past this; a whole layer's batch takes seconds
export const EVAL_TIMEOUT = 2min
# the verbs that do their work while evaluated (update, backup, restore) instead of declaring it
export const VERB_WORK_TIMEOUT = 30min
# a config home no login has: profile-load under it reads no profile and no options but PROFILE_FILE
const PROFILE_HOME_NONE = "/nonexistent"

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
    let natives = native-read ($markers | path dirname)
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
    let cache = if (is-admin) { $SYSTEM_STATE | path join discover.nuon } else { xdg cache dotfiles discover.nuon }
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
    let known = $ids | reduce --fold {} {|i, acc| $acc | insert $i true }
    let group_ids = $modules | group-by group | items {|g, ms| {group: $g, ids: $ms.id} } | reduce --fold {} {|r, acc| $acc | insert $r.group $r.ids }
    let grouped = $modules | where group != "" | get id
    let group_preds = $group_deps | reduce --fold {} {|g, acc|
        $acc | insert $g.group ($g.deps | each {|d| $group_ids | get --optional $d | default [] } | flatten)
    }
    let with_preds = $modules | each {|m|
        let by_group = if $m.group == "" { $grouped } else { $group_preds | get $m.group }
        $m | insert after ($by_group | append $m.meta.deps | where {|a| $a != $m.id and ($known | get --optional $a | default false) } | uniq)
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

# --private runs under umask 077, for a backup writing into configs/secrets/. --timeout bounds the child (EVAL_TIMEOUT
# by default); a batch past it is evaluated again module by module, so the one that hangs fails alone. The modules of
# a batch evaluate in parallel (declarations only, no effects), results in input order: a theme switch on a laptop
# spent half its time here one module after another.
export def modules-eval [modules: table, verb: string, cfgs: record, args: list, --private, --timeout: duration]: nothing -> table {
    if ($modules | is-empty) { return [] }
    let timeout = $timeout | default $EVAL_TIMEOUT
    let calls = $modules | enumerate | each {|m|
        let cfg = $cfgs | get $m.item.id | to nuon
        $"{id: ($m.item.id | to nuon), run: {|| cd ($m.item.dir | to nuon); with-env {DOTFILES_MODULE: ($m.item.id | to nuon)} { m($m.index) ($verb) ($cfg) ($args | each { to nuon } | str join ' ') } }}"
    }
    let body = $"[($calls | str join ' ')] | par-each --keep-order {|c| try { {id: $c.id, ok: true, decls: \(do $c.run | decls-flatten\), error: null} } catch {|e| {id: $c.id, ok: false, decls: [], error: \(cause-text \(cause-from-error $e\)\)} } } | to nuon | save --force $env.DOT_EVAL_OUT"
    let run = [(nu-bin) --no-config-file -I $LIB_DIR -c (native-script ($modules | select dir) $"use module.nu *\nuse cause.nu [cause-from-error cause-text]\n($body)")]
    let out_file = mktemp --tmpdir
    let bounded_run = bounded $timeout {
        with-env {DOT_EVAL_OUT: $out_file} {
            if $private { ^bash -c 'umask 077 && exec "$@"' private ...$run | complete } else { ^($run | first) ...($run | skip 1) | complete }
        }
    }
    if $bounded_run.timed_out {
        rm --force $out_file
        if ($modules | length) == 1 {
            log-warn $"($modules.0.id): evaluating ($verb) still running after ($timeout), killed"
            return [{id: $modules.0.id, ok: false, decls: [], error: $"evaluating ($verb) timed out after ($timeout)"}]
        }
        log-warn $"evaluating ($verb) of ($modules | length) modules still running after ($timeout), killed: evaluating each alone"
        return ($modules | each {|m| modules-eval [$m] $verb $cfgs $args --private=$private --timeout $timeout } | flatten)
    }
    let out = $bounded_run.value
    child-warnings $out.stderr
    let result = if $out.exit_code == 0 and ($out_file | path type) == "file" { open --raw $out_file | from nuon } else { null }
    rm --force $out_file
    if $result == null {
        error make {msg: $"evaluating ($verb) exited ($out.exit_code): ($out.stdout)($out.stderr)"}
    }
    $result
}

# Each module's packages, its packages hook merged in, native ones dropped on WSL; ok is false when the hook failed and
# the module declares its meta alone.
export def modules-packages-each [modules: table, platform: record]: nothing -> table {
    let wsl = $platform.form_factor == "wsl"
    let computing = $modules | where {|m| "packages" in $m.native }
    let results = modules-eval $computing packages ($computing | reduce --fold {} {|m, acc| $acc | insert $m.id $m.cfg }) []
    $results | where not ok | each { log-warn $"($in.id): packages failed, checking its meta alone: ($in.error)" } | ignore
    let computed = $results | reduce --fold {} {|r, acc| $acc | insert $r.id {ok: $r.ok, decls: ($r.decls | get --optional 0 | default {})} }
    $modules | each {|m|
        let hook = $computed | get --optional $m.id | default {ok: true, decls: {}}
        let p = $m.meta.packages | merge deep --strategy=append $hook.decls
        {id: $m.id, pacman: ($p.pacman ++ (if $wsl { [] } else { $p.native })), flatpak: $p.flatpak, nix: $p.nix, ok: $hook.ok}
    }
}

# The pacman, flatpak and nix packages every enabled module on this platform declares.
export def modules-packages [repo: path, modules: table, platform: record]: nothing -> record {
    let declared = modules-packages-each ($modules | where {|m| $m.selected and $m.cfg.enable }) $platform
    # a broken module or a failed packages hook declares too little: callers must not remove by this list
    let incomplete = ($declared | where not ok | get id) ++ ($modules | where {|m| $m.selected and ($m.broken? | default false) } | get id)
    {
        pacman: ($declared | each { $in.pacman } | flatten | append $platform.extra_packages | uniq | sort)
        flatpak: ($declared | reduce --fold {} {|p, acc| $acc | merge $p.flatpak })
        nix: ($declared | each { $in.nix } | flatten | uniq | sort)
        incomplete: $incomplete
    }
}

# What a packages hook is evaluated under to learn every package it can want, whoever runs it on whichever machine:
# each repo profile and none, as the env profile-load reads (a config home that does not exist hides the caller's own
# profile and options), and each value a platform's options file sets.
export def packages-every-context [repo: path]: nothing -> record {
    let profiles = glob ($repo | path join profiles *.nuon) | sort | append "" | each {|f| {PROFILE_FILE: $f, XDG_CONFIG_HOME: $PROFILE_HOME_NONE} }
    let values = glob ($repo | path join platforms *.options.nuon) | sort | each {|f|
        open $f | items {|id, opts| $opts | items {|name, value| {id: $id, name: $name, value: $value} } } | flatten
    } | flatten
    {profiles: $profiles, values: $values}
}

# Every package a module can declare: meta's pacman and native, flatpak and nix for apps of theirs, and what its
# packages hook returns under each profile of every and each option value from defaults, choices, bools and platforms.
export def module-packages-every [m: record, every: record]: nothing -> list<string> {
    let managers = [[name wanted]; [flatpak ($m.meta.packages.flatpak | is-not-empty)] [nix ($m.meta.packages.nix | is-not-empty)]]
    let own = $m.meta.packages.pacman ++ $m.meta.packages.native ++ ($managers | where wanted | get name)
    if "packages" not-in $m.native { return $own }
    let defaults = $m.options | items {|name, spec| {name: $name, value: $spec.default} } | reduce --fold ($m.cfg | upsert enable true) {|o, acc|
        $acc | upsert $o.name $o.value
    }
    let variants = $m.options | items {|name, spec|
        let set = $every.values | where id == $m.id and name == $name | get value
        let type = $spec.type | str trim --right --char "?"
        let nullable = if $type != $spec.type { [null] } else { [] }
        let values = $spec.choices? | default (if $type == bool { [true false] } else { [] }) | append $nullable | append $set | uniq
        $values | each {|v| $defaults | upsert $name $v }
    } | flatten | prepend $defaults | uniq
    let runs = $every.profiles | each {|p| $variants | each {|cfg| {env: $p, cfg: $cfg} } } | flatten
    let hooked = $runs | par-each {|r|
        with-env $r.env { modules-eval [$m] packages {$m.id: $r.cfg} [] } | get 0.decls | get --optional 0 | default {} | select --optional pacman native | values | flatten | compact
    } | flatten
    $own ++ ($hooked | sort) | compact | uniq
}
