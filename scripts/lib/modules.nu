use log.nu *
use state.nu [LIB_DIR nu-bin SYSTEM_STATE]

const SELF = path self

export const VERBS = [link unlink system theme apply backup restore check]
# exports the engine calls that are not run as a layer's verb
const HOOKS = [detect packages]
const MARKER = "mod.nu"
# repo-root dirs that link like modules, after every configs module
const ROOT_MODULES = [scripts skills weblinks]
const META_DEFAULT = {deps: [], packages: {pacman: [], native: [], flatpak: {}, nix: []}, serial: false}

def names-read [file: path]: nothing -> list<string> {
    if not ($file | path exists) { return [] }
    open --raw $file | lines | each { split row "#" | first | str trim | split row " " | first } | where $it != ""
}

def native-script [mods: list<record>, body: string]: nothing -> string {
    let uses = $mods | enumerate | each {|m| $"module m($m.index) { export use ($m.item.dir | to nuon) *; export const DOT_MODULE = true }\nuse m($m.index)" }
    $uses | append $body | str join "\n"
}

# a child's own log lines keep their level and are in the run log already; any other stderr (a deprecation, a module's
# print -e) is a warning, never part of its answer
def child-warnings [stderr: string]: nothing -> nothing {
    let tag = $"($env.LOG_TAG? | default dotfiles): "
    let lines = $stderr | lines | where ($it | str trim) != ""
    $lines | where ($it | str starts-with $tag) | each { print -e $in } | ignore
    let other = $lines | where not ($it | str starts-with $tag)
    if ($other | is-not-empty) { log-warn ($other | str join "\n") }
}

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
    # one broken mod.nu must not hide every other: it is reported and left out of this run
    let broken = $dirs | each {|dir| {dir: $dir, check: (^(nu-bin) --no-config-file -I $LIB_DIR -c $"use ($dir | to nuon)" | complete)} }
        | where check.exit_code != 0
    if ($broken | is-empty) { error make {msg: $"reading the modules failed: ($found.stderr)"} }
    $broken | each { log-err $"($in.dir)/mod.nu does not parse, left out:\n($in.check.stderr | str trim)" } | ignore
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

export def modules-discover [repo: path, groups: list<string>]: nothing -> table {
    let configs = $repo | path join configs
    let markers = glob $"($configs)/*/**/($MARKER)" | append ($ROOT_MODULES | each {|r| glob $"($repo)/($r)/($MARKER)" } | flatten)
    let inputs = $markers | append (glob $"($configs)/**/dependencies.txt") | append $SELF
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
    $found | insert selected {|m| $m.group == "" or $m.group in $groups }
}

# byte-wise id order breaks ties, so an undeclared order is the sorted one
export def modules-graph [repo: path, modules: table]: nothing -> table {
    let ids = $modules.id
    let group_deps = $modules.group | uniq | where $it != "" | each {|g|
        {group: $g, deps: (names-read ($repo | path join configs $g dependencies.txt) | append (if $g == "base" { [] } else { [base] }))}
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
    mut done = {}
    mut order = []
    mut left = $with_preds | sort-by id
    while ($left | is-not-empty) {
        let finished = $done
        let ready = $left | where {|m| $m.after | all {|a| $a in $finished } }
        if ($ready | is-empty) {
            error make {msg: $"dependency cycle among ($left.id | str join ' ')"}
        }
        let next = $ready | first
        let level = $next.after | each {|a| $finished | get $a } | append (-1) | math max | $in + 1
        $done = $done | insert $next.id $level
        $order = $order | append ($next | insert level $level)
        $left = $left | where id != $next.id
    }
    $order
}

# --private: umask 077, for a backup writing into secrets/
export def modules-eval [modules: table, verb: string, cfgs: record, args: list, --private]: nothing -> table {
    if ($modules | is-empty) { return [] }
    let calls = $modules | enumerate | each {|m|
        let name = $m.item.dir | path basename
        let cfg = $cfgs | get $m.item.id | to nuon
        $"{id: ($m.item.id | to nuon), run: {|| cd ($m.item.dir | to nuon); with-env {DOTFILES_MODULE: ($m.item.id | to nuon)} { m($m.index) ($verb) ($cfg) ($args | each { to nuon } | str join ' ') } }}"
    }
    # through a file in nuon, not stdout in json: a module may print, and a filesize or duration must stay one
    let body = $"[($calls | str join ' ')] | each {|c| try { {id: $c.id, ok: true, decls: \(do $c.run | decls-flatten\), error: null} } catch {|e| {id: $c.id, ok: false, decls: [], error: $e.msg} } } | to nuon | save --force $env.DOT_EVAL_OUT"
    let run = [(nu-bin) --no-config-file -I $LIB_DIR -c (native-script ($modules | select dir) $"use module.nu *\n($body)")]
    let out_file = mktemp --tmpdir
    let out = with-env {DOT_EVAL_OUT: $out_file} {
        if $private { ^bash -c 'umask 077 && exec "$@"' private ...$run | complete } else { ^($run | first) ...($run | skip 1) | complete }
    }
    child-warnings $out.stderr
    # a child killed outside its per-module try exits without the file, whatever its code says
    let result = if $out.exit_code == 0 and ($out_file | path type) == "file" { open --raw $out_file | from nuon } else { null }
    rm --force $out_file
    if $result == null {
        error make {msg: $"evaluating ($verb) exited ($out.exit_code): ($out.stdout)($out.stderr)"}
    }
    $result
}


export def modules-packages [repo: path, modules: table, platform: record]: nothing -> record {
    let wsl = $platform.form_factor == "wsl"
    let selected = $modules | where {|m| $m.selected and $m.cfg.enable }
    let computing = $selected | where {|m| "packages" in $m.native }
    let computed = modules-eval $computing packages ($computing | reduce --fold {} {|m, acc| $acc | insert $m.id $m.cfg }) []
        | reduce --fold {} {|r, acc|
            if not $r.ok { log-warn $"($r.id): packages failed: ($r.error)" }
            $acc | insert $r.id ($r.decls | get --optional 0 | default {})
        }
    let on = $selected | each {|m| $m | update meta.packages {|x| $x.meta.packages | merge deep --strategy=append ($computed | get --optional $m.id | default {}) } }
    {
        pacman: ($on | each {|m| $m.meta.packages.pacman ++ (if $wsl { [] } else { $m.meta.packages.native }) } | flatten | append $platform.extra_packages | uniq | sort)
        flatpak: ($on | reduce --fold {} {|m, acc| $acc | merge $m.meta.packages.flatpak })
        nix: ($on | each { $in.meta.packages.nix } | flatten | uniq | sort)
    }
}
