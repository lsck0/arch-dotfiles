# Module discovery, ordering and evaluation, each batch in one child nu.

use log.nu *
use state.nu [LIB_DIR nu-bin SYSTEM_STATE xdg save-atomic]

const SELF = path self
const REPO = path self ../..

# the verbs the engine calls on a module, and the hooks it reads while loading; nothing else is dispatched by name
export const VERBS = [link system theme apply backup restore update]
export const HOOKS = [detect packages]
const MARKER = "mod.nu"
const DEPENDENCIES = "dependencies.txt"
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

# The mod.nu and dependencies.txt files under configs/, absolute. git's index and untracked list in a checkout and its
# secrets submodule, which skip ignored trees (qmk_firmware's 40k files); a walk where either has no git (the root copy).
export def modules-markers [repo: path]: nothing -> list<string> {
    let configs = $repo | path join configs
    let dirs = [$repo ($configs | path join $SECRETS_GROUP)] | where ($it | path exists)
    let listed = $dirs | each {|d|
        if not ($d | path join .git | path exists) { return null }
        let within = if $d == $repo { "configs/" } else { "" }
        let found = ^git -C $d ls-files -z --cached --others --exclude-standard --deduplicate -- $":\(glob\)($within)**/($MARKER)" $":\(glob\)($within)**/($DEPENDENCIES)" | complete
        if $found.exit_code != 0 { return null }
        $found.stdout | split row (char nul) | where $it != "" | each {|f| $d | path join $f }
    }
    # each drops a null: a dir without its list is one row short
    if ($listed | length) != ($dirs | length) {
        return (glob $"($configs)/**/{($MARKER),($DEPENDENCIES)}" --no-dir --exclude $SECRETS_DATA)
    }
    let data = $SECRETS_DATA | each { str replace "/**" "/" | $"($configs)/($in)" }
    $listed | flatten | where {|f| ($f | path exists) and not ($data | any {|p| $f | str starts-with $p }) } | uniq
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
        let sibling_deps = if $root { [] } else { names-read ($dir | path join $DEPENDENCIES) | each {|d| $"($group)/($d)" } }
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
    let found = modules-markers $repo
    let markers = $found | where ($it | path basename) == $MARKER and ($it | path dirname) != $configs
        | append ($ROOT_MODULES | each {|r| $repo | path join $r $MARKER } | where ($it | path exists))
    let inputs = $markers | append ($found | where ($it | path basename) == $DEPENDENCIES) | append $SELF
    let key = ls --full-paths ...$inputs | select name size modified | to nuon | hash sha256
    # the caller's own cache, never root's: a user plans the system layer too
    let cache = if (is-admin) { $SYSTEM_STATE | path join discover.nuon } else { xdg cache dotfiles discover.nuon }
    # an unreadable or empty cache (a cut-off write) is a miss, rescanned and written anew
    let cached = try { let c = open $cache; {key: $c.key, modules: $c.modules} } catch { {key: ""} }
    let found = if $cached.key == $key { $cached.modules } else {
        let scanned = modules-scan $repo $markers
        if not ($scanned | any { $in.broken }) {
            mkdir ($cache | path dirname)
            {key: $key, modules: $scanned} | to nuon | save-atomic $cache
        }
        $scanned
    }
    $found | insert selected {|m| $m.group in ["" $SECRETS_GROUP] or $m.group in $groups or $m.id in $groups }
}

# The modules root runs a hook of: each with a system verb or a packages hook (a broken one counted, unknown), and of
# the others those with a detect a root-run module reads through meta.deps or meta.reads. Root probes no other detect.
export def modules-root-run [modules: table]: nothing -> list<string> {
    let running = $modules | where {|m| $m.broken or "system" in $m.native or "packages" in $m.native }
    let read = $running | each {|m| $m.meta.deps ++ ($m.meta.reads? | default []) } | flatten | uniq
    let detecting = $modules | where {|m| "detect" in $m.native and $m.id in $read } | get id
    $running.id ++ $detecting | uniq
}

# The modules in run order, each with after (what it waits for) and level; ties break by sorted id. Dependency
# edges are reasoned at group granularity (a module waits on a dependency group as a whole, plus its own meta.deps)
# so the Kahn sort below never walks the full module x edge product, only the small group and meta.deps graphs.
export def modules-graph [repo: path, modules: table]: nothing -> table {
    let ids = $modules.id
    let groups = $modules.group | uniq | where $it != ""
    let group_id_map = $modules | where group != "" | group-by group | items {|g, ms| [$g $ms.id] } | into record
    let grouped = $modules | where group != "" | get id
    let root_members = $modules | where group == "" | get id

    let group_info = $groups | each {|g|
        let dep_names = (if $g == $SECRETS_GROUP { $groups | where $it != $g } else {
            names-read ($repo | path join configs $g $DEPENDENCIES) | append (if $g == "base" { [] } else { [base] })
        } | uniq | where $it in $groups)
        {group: $g, dep_groups: $dep_names, after: ($dep_names | each {|d| $group_id_map | get $d } | flatten | uniq)
            total: ($group_id_map | get $g | length)}
    }
    let group_info = $group_info
        | append {group: "", dep_groups: $groups, after: $grouped, total: ($root_members | length)}
    let group_total = $group_info | each {|g| [$g.group $g.total] } | into record
    # reverse edges at group granularity: which groups wait on group g
    let group_dependents = $group_info
        | each {|g| [$g.group ($group_info | where ($g.group in $it.dep_groups) | get group)] } | into record

    let with_after = $modules
        | join ($group_info | select group after) group
        | join ($group_info | select group dep_groups) group

    # meta.deps touch only the handful of modules declaring them; everyone else keeps the group-level after as is
    let plain_rows = $with_after | where ($it.meta.deps | is-empty) | insert meta_extra []
    let meta_rows = $with_after | where ($it.meta.deps | is-not-empty) | each {|m|
        let extra = $m.meta.deps | where {|a| $a != $m.id and $a in $ids } | uniq
        $m | update after ($m.after | append $extra | uniq) | insert meta_extra $extra
    }
    let sorted = ($plain_rows | append $meta_rows) | sort-by id
    let position = $sorted | enumerate | each {|r| [$r.item.id $r.index] } | into record
    let meta_dependents = $meta_rows
        | each {|m| $m.meta_extra | each {|d| {after: $d, id: $m.id} } } | flatten | group-by after

    let groups_waiting = $group_info | each {|g| [$g.group ($g.dep_groups | length)] } | into record
    mut group_done = $group_info | each {|g| [$g.group 0] } | into record
    mut group_max_level = {}
    mut pending_groups = $groups_waiting
    mut pending_meta = $sorted | each {|r| [$r.id ($r.meta_extra | length)] } | into record
    mut ready = $sorted | where {|r| ($groups_waiting | get $r.group) == 0 and ($r.meta_extra | is-empty) } | get id | sort

    mut done = {}
    mut order = []
    while ($ready | is-not-empty) {
        let id = $ready | first
        $ready = $ready | skip 1
        let next = $sorted | get ($position | get $id)
        let group_levels = $group_max_level
        let levels = $done
        let level = 1 + ([-1] ++ ($next.dep_groups | each {|g| $group_levels | get --optional $g | default (-1) })
            ++ ($next.meta_extra | each {|d| $levels | get --optional $d | default (-1) }) | math max)
        $done = $done | insert $id $level
        $order = $order | append ($next | reject dep_groups meta_extra | insert level $level)

        mut freed = []
        let g = $next.group
        let prior_max = $group_max_level | get --optional $g | default (-1)
        if $prior_max < $level { $group_max_level = $group_max_level | upsert $g $level }
        let gdone = ($group_done | get $g) + 1
        $group_done = $group_done | upsert $g $gdone
        if $gdone == ($group_total | get $g) {
            for dep in ($group_dependents | get --optional $g | default []) {
                let p = ($pending_groups | get $dep) - 1
                $pending_groups = $pending_groups | upsert $dep $p
                if $p == 0 {
                    let members = if $dep == "" { $root_members } else { $group_id_map | get $dep }
                    for mid in $members {
                        if ($pending_meta | get $mid) == 0 { $freed = $freed | append $mid }
                    }
                }
            }
        }
        for dependent in ($meta_dependents | get --optional $id | default [] | get --optional id | default []) {
            let p = ($pending_meta | get $dependent) - 1
            $pending_meta = $pending_meta | upsert $dependent $p
            if $p == 0 {
                let dg = ($sorted | get ($position | get $dependent)).group
                if ($pending_groups | get $dg) == 0 { $freed = $freed | append $dependent }
            }
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
    let results = modules-eval $computing packages ($computing | each {|m| [$m.id $m.cfg] } | into record) []
    $results | where not ok | each { log-warn $"($in.id): packages failed, checking its meta alone: ($in.error)" } | ignore
    let computed = $results | each {|r| [$r.id {ok: $r.ok, decls: ($r.decls | get --optional 0 | default {})}] } | into record
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
    let defaults = $m.cfg | upsert enable true | merge ($m.options | items {|name, spec| [$name $spec.default] } | into record)
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
