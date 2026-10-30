# One layer's run: load, plan (unchanged modules skipped), apply in dependency order as parallel jobs.

use log.nu *
use state.nu [LIB_DIR]
use platform.nu [platform-load platform-env]
use profile.nu [profile-load]
use options.nu [options-resolve]
use modules.nu [modules-discover modules-graph modules-eval]
use converge.nu [state-read observe recorded-hashes decls-check plan-module apply-module state-write mode-normal]
use secrets.nu [secret-is-plaintext OWNER_WITNESS]

const HASH_STAMP = '%P %s %T@\n'
const EXEC_PASSES_MAX = 3
const NOTE_PREFIX = "note:"
const REVERT_VERBS = [link system]
# a link source can be a dead mount: bound the probe, a timeout counts as gone
const LINK_PROBE_TIMEOUT_S = 2
# a hung theme verb is killed after this; the run goes on
export const THEME_VERB_TIMEOUT = 60sec

def eval-env [ctx: record]: nothing -> record {
    platform-env $ctx.platform | merge {DOT_LAYER: $ctx.layer, DOTFILES: $ctx.repo}
}

def detect [ctx: record, modules: table]: nothing -> record {
    let probing = $modules | where {|m| "detect" in $m.native }
    if ($probing | is-empty) { return {} }
    let cfgs = $probing | reduce --fold {} {|m, acc| $acc | insert $m.id ($m.options | items {|k, s| {k: $k, v: $s.default} } | reduce --fold {} {|o, a| $a | insert $o.k $o.v }) }
    with-env (eval-env $ctx) { modules-eval $probing detect $cfgs [] } | each {|r|
        if not $r.ok { log-warn $"($r.id): detect failed, its options stay unset: ($r.error)" }
        {id: $r.id, values: ($r.decls | get --optional 0 | default {})}
    } | reduce --fold {} {|r, acc| $acc | insert $r.id $r.values }
}

# Expands an app-dirs.conf value as environment.d does: ${HOME}, then ${VAR:-default} from the env.
def app-dirs-expand []: string -> string {
    let text = $in | str replace --all '${HOME}' $nu.home-dir
    $text | parse --regex '(?<all>\$\{(?<k>[A-Za-z_][A-Za-z0-9_]*):-(?<d>[^}]*)\})'
    | reduce --fold $text {|m, acc| $acc | str replace $m.all ($env | get --optional $m.k | default "" | if ($in | is-empty) { $m.d } else { $in }) }
}

# The install chain has no environment.d yet: load base/xdg's app dirs; session values win.
def --env app-dirs-load [repo: path]: nothing -> nothing {
    let file = $repo | path join configs base xdg app-dirs.conf
    if not ($file | path exists) { return }
    open --raw $file | lines | parse --regex '^(?<k>[A-Za-z_][A-Za-z0-9_]*)=(?<v>.*)$'
    | where {|e| ($env | get --optional $e.k) == null }
    | each {|e| {($e.k): ($e.v | app-dirs-expand)} }
    | reduce --fold {} {|e, acc| $acc | merge $e }
    | load-env
}

# The run context for a layer: repo, platform, profile and every discovered module with its resolved options.
export def --env pipeline-load [repo: path, layer: string]: nothing -> record {
    $env.DOT_LAYER = $layer
    if $layer == "user" { app-dirs-load $repo }
    let platform = span platform {} { platform-load $repo }
    let profile = if $layer == "user" { profile-load } else { null }
    let found = span discover {} { modules-discover $repo $platform.groups }
    let base = {repo: $repo, layer: $layer, platform: $platform, profile: $profile}
    let detected = span detect {} { detect $base $found }
    let resolved = span resolve {} { options-resolve $found $platform $profile $detected }
    if ($resolved.errors | is-not-empty) {
        error make {msg: $"options:\n($resolved.errors | str join "\n")"}
    }
    let values = $resolved.rows | reduce --fold {} {|r, acc| $acc | insert $r.id $r }
    let modules = $found | each {|m|
        let row = $values | get $m.id
        let deps = $m.meta.deps | where $it in ($values | columns) | reduce --fold {} {|d, acc| $acc | insert $d ($values | get $d | get values) }
        $m | insert cfg ($row.values | insert deps $deps) | insert sources $row.sources
    }
    $base | insert modules $modules
}

def stamp [dir: path]: nothing -> string {
    ^find $dir -type f -not -name '*.log' -not -name '*.test.nu' -not -name '*.test.sh' -printf $HASH_STAMP | lines | sort | str join "\n"
}

# Imports outside the module's dir, followed transitively, so a change there re-runs the module.
def imports-outside [dir: path]: nothing -> list<string> {
    mut seen = []
    mut todo = glob ($dir | path join "**" "*.nu")
    while ($todo | is-not-empty) {
        let file = $todo | first
        $todo = $todo | skip 1
        let found = open --raw $file | lines
            | parse --regex '^\s*(?:export\s+)?(?:use|source|source-env)\s+(?<p>\.{1,2}/\S+\.nu)'
            | get p | each {|p| $file | path dirname | path join $p | path expand }
            | where {|f| not ($f | str starts-with $"($dir)/") and not ($f | str starts-with $LIB_DIR) and $f not-in $seen and ($f | path exists) }
        $seen = $seen ++ $found
        $todo = $todo ++ $found
    }
    $seen | sort
}

# A path that cannot be read (a nas link while the nas is down) counts as missing, never a crash.
def stat [repo: path, paths: list<string>]: nothing -> string {
    let found = $paths | each {|p| if ($p | str starts-with "/") or ($p | str starts-with "~") { $p | path expand } else { $repo | path join $p } } | each {|p| try { glob $p } catch { [] } } | flatten | uniq
    if ($found | is-empty) { return "" }
    $found | each {|f| try { ls --directory --full-paths $f | get 0 | select name size modified } catch { {name: $f} } } | to nuon
}

def outputs-clean [outputs: list<record>, seen: record]: nothing -> bool {
    $outputs | all {|o|
        let obs = $seen.paths | get --optional $o.target
        match $o.kind {
            # a record from before modes were kept has none, and only its hash counts
            "file" => ($obs.hash? == $o.hash and ($o.mode? == null or (mode-normal $obs.mode?) == (mode-normal $o.mode)))
            "link" => ($obs.link? == $o.source)
            "exec" => ($o.source | path exists)
            "unit" => (match ($o.state? | default enabled) { "disabled" => (($seen.units | get --optional $o.target) != "enabled"), $s => (($seen.units | get --optional $o.target) == $s) })
            # an owned merge is no output of its own: the module's inputs decide whether it merges again
            _ => true
        }
    }
}

def scope-of [layer: string]: nothing -> string {
    if $layer == "system" { "system" } else { "user" }
}

def eval-plan [ctx: record, mods: table, verb: string, args: list, prev: record, force: bool]: nothing -> table {
    let on = $mods | where cfg.enable
    let off = $mods | where not $it.cfg.enable | each {|m| {id: $m.id, ok: true, decls: [], error: null} }
    let evaluated = if ($on | is-empty) { [] } else { span eval {verb: $verb} { with-env (eval-env $ctx) { modules-eval $on $verb ($on | reduce --fold {} {|m, acc| $acc | insert $m.id $m.cfg }) $args } } }
        | append $off
        | each {|e| if not $e.ok { $e } else { try { decls-check $e.id $e.decls; $e } catch {|err| $e | merge {ok: false, decls: [], error: $err.msg} } } }
    let decls = $evaluated | reduce --fold [] {|e, acc| $acc ++ $e.decls }
    let all_targets = $decls | get --optional target | default [] | uniq
    let olds = $prev | values | reduce --fold [] {|p, acc| $acc ++ $p }
    let paths = $decls | where kind not-in [unit exec step] | get --optional target | default [] | append ($olds | where kind not-in [unit exec] | get --optional target | default [])
    let units = $decls | where kind == unit | get --optional target | default [] | append ($olds | where kind == unit | get --optional target | default [])
    let seen = span observe {} { observe $paths $units (scope-of $ctx.layer) }
    let recorded = recorded-hashes
    $evaluated | each {|r|
        if not $r.ok { return {id: $r.id, actions: [], error: $r.error} }
        try {
            {id: $r.id, actions: (plan-module $r.id $r.decls ($prev | get $r.id) $seen $recorded $ctx.repo $force $all_targets), error: null}
        } catch {|err| {id: $r.id, actions: [], error: $"plan: ($err.msg)"} }
    }
}

# root's secrets arrive in a fresh dir each run: their content, not their path, decides whether a module re-runs
# root gets the secrets as DOTFILES_SECRETS, the user layer reads the checkout's keys/ (size and mtime: 60M of keys)
def secrets-stamp [repo: path]: nothing -> string {
    let dir = $env.DOTFILES_SECRETS? | default ""
    if $dir != "" and ($dir | path exists) {
        return (glob ($dir | path join "**" "*") --no-dir | sort | each {|f| $"($f | path relative-to $dir) (open --raw $f | hash sha256)" } | str join "\n" | hash sha256)
    }
    let keys = $repo | path join configs secrets keys
    if not ($keys | path exists) { return "" }
    ls --all ($keys | path join "**" "*" | into glob) | where type == file | sort-by name
    | each {|f| $"($f.name) ($f.size) ($f.modified)" } | str join "\n" | hash sha256
}

# Unchanged modules are skipped unevaluated; a disabled one plans its removals.
export def pipeline-plan [ctx: record, verb: string, ids: list<string>, force: bool, args: list = []]: nothing -> table {
    let unknown = $ids | where $it not-in $ctx.modules.id
    if ($unknown | is-not-empty) {
        error make {msg: $"no module ($unknown | str join ', '); dot plan --modules lists them"}
    }
    let broken = $ctx.modules | where {|m| $m.broken and (($ids | is-empty) or $m.id in $ids) }
    if ($ids | is-not-empty) and ($broken | is-not-empty) {
        error make {msg: $"($broken.id | str join ', '): mod.nu does not parse"}
    }
    let active = $ctx.modules | where {|m| $verb in $m.verbs and $m.cfg.enable and (($ids | is-empty) or $m.id in $ids) }
    let retired = if $verb not-in $REVERT_VERBS { [] } else {
        $ctx.modules | where {|m| not $m.cfg.enable and not $m.broken and $verb in $m.native and (($ids | is-empty) or $m.id in $ids) and ((state-read $m.id $verb).outputs | is-not-empty) }
    }
    let graph = span graph {} { modules-graph $ctx.repo ($active ++ $retired) }
    # the lib's own imports outside it (the wallust palette) count for every module
    let lib_imported = imports-outside $LIB_DIR | each {|f| $"($f) (open --raw $f | hash sha256)" } | str join "\n"
    let global = [
        (stamp $LIB_DIR) $lib_imported ($ctx.platform.facts | to nuon) ($ctx.profile.capabilities? | default [] | to nuon)
        (secret-is-plaintext ($ctx.repo | path join $OWNER_WITNESS)) $verb ($args | to nuon)
        (secrets-stamp $ctx.repo)
    ] | str join "\n"
    let natives = $graph | where $verb in $it.native | each {|m|
        let prev = state-read $m.id $verb
        let outside = $prev.outputs | where kind in [file link] and source != null and not ($it.source | str starts-with $m.dir)
        # a link depends only on its source existing; the probe is bounded, a stat() on a dead autofs mount blocks
        let links = $outside | where kind == link | get source
            | each {|s| $"($s) ((do { ^timeout $LINK_PROBE_TIMEOUT_S test -e $s } | complete).exit_code == 0)" }
            | str join "\n"
        let imported = imports-outside $m.dir | each {|f| $"($f) (open --raw $f | hash sha256)" } | str join "\n"
        let input = [$global (stamp $m.dir) $imported ($m.cfg | to nuon) (stat $ctx.repo ($m.meta.inputs? | default [])) (stat $ctx.repo ($outside | where kind == file | get source)) $links] | str join "\n" | hash sha256
        {id: $m.id, prev: $prev, input: $input, volatile: ($m.meta.volatile? | default false)}
    }
    let prev_targets = $natives | reduce --fold [] {|n, acc| $acc ++ $n.prev.outputs }
    let before = span observe {} { observe ($prev_targets | where kind not-in [unit exec] | get --optional target | default []) ($prev_targets | where kind == unit | get --optional target | default []) (scope-of $ctx.layer) }
    let fresh = $natives | where {|n| not $force and not $n.volatile and $n.id not-in $retired.id and $n.input == $n.prev.input and (outputs-clean $n.prev.outputs $before) } | get id
    let to_eval = $graph | where {|m| $verb in $m.native and $m.id not-in $fresh }
    let prev = $natives | reduce --fold {} {|n, acc| $acc | insert $n.id $n.prev.outputs }
    let planned = eval-plan $ctx $to_eval $verb $args $prev $force
    let rows = $graph | each {|m|
        let native = $natives | where id == $m.id | get --optional 0
        let row = {id: $m.id, dir: $m.dir, after: $m.after, level: $m.level, serial: $m.meta.serial, cfg: $m.cfg, options: $m.options, force: $force}
        if $native == null {
            $row | merge {native: false, skipped: false, input: "", prev: [], actions: [], error: null}
        } else if $m.id in $fresh {
            $row | merge {native: true, skipped: true, input: $native.input, prev: $native.prev.outputs, actions: [], error: null}
        } else {
            let p = $planned | where id == $m.id | first
            $row | merge {native: true, skipped: false, input: $native.input, prev: $native.prev.outputs, actions: $p.actions, error: $p.error}
        }
    }
    $rows ++ ($broken | where selected | each {|m|
        {id: $m.id, dir: $m.dir, after: [], level: 0, serial: false, cfg: {}, options: {}, native: true, skipped: false, input: "", prev: [], actions: [], error: "mod.nu does not parse"}
    })
}

# Applies a module's actions, evaluating it again after an exec created something, up to EXEC_PASSES_MAX passes.
def native-run [ctx: record, m: record, verb: string, args: list]: nothing -> record {
    mut actions = $m.actions
    mut prev = $m.prev
    mut outcomes = []
    mut pass = 1
    mut converged = false
    loop {
        let current = $actions
        let done = with-env (platform-env $ctx.platform) { apply-module $current $m.dir (scope-of $ctx.layer) }
        $outcomes = $outcomes ++ $done
        let ran = $done | where {|o| $o.kind == "exec" and $o.ok and $o.decl.creates? != null }
        let failed = $done | where not ok
        if ($ran | is-empty) or ($failed | is-not-empty) or $pass >= $EXEC_PASSES_MAX {
            $converged = ($ran | is-empty) and ($failed | is-empty)
            if ($ran | is-not-empty) and ($failed | is-empty) { log-warn $"($m.id): still running ($ran.target | str join ', ') after ($pass) passes, evaluated again next run" }
            state-write $m.id $verb (if $converged { $m.input } else { "" }) $actions $done $prev
            break
        }
        state-write $m.id $verb "" $actions $done $prev
        $prev = (state-read $m.id $verb).outputs
        $pass += 1
        log-info $"($m.id): pass ($pass) after ($ran.target | str join ', ')" {kind: pass}
        let outputs = $prev
        let again = eval-plan $ctx [$m] $verb $args {$m.id: $outputs} ($m.force? | default false) | first
        if $again.error != null { error make {msg: $again.error} }
        $actions = $again.actions
    }
    let failed = $outcomes | where not ok
    let kept = $actions | where kind == drift | each {|a| $"kept ($a.target): ($a.reason); dot module adopt it or apply --force" }
    let lines = $outcomes | each {|o| [$"($o.kind) ($o.target)(if $o.ok { '' } else { $': ($o.error)' })"] ++ ($o.output | lines | where ($it | str trim | str starts-with $NOTE_PREFIX) | each { $"  ($in)" }) } | flatten
    {ok: ($failed | is-empty), log: ($lines ++ $kept | str join "\n"), outcomes: $outcomes, error: ($failed | get --optional 0.error)}
}

def module-run [ctx: record, m: record, verb: string, args: list]: nothing -> record {
    let start = date now
    let result = with-env {DOTFILES_MODULE: $m.id, DOT_VERB: $verb} {
        span $m.id {module: $m.id, verb: $verb} {
            if not $m.native or $m.skipped {
                {ok: true, log: "", outcomes: [], error: null}
            } else if $m.error != null {
                {ok: false, log: "", outcomes: [], error: $m.error}
            } else {
                try { native-run $ctx $m $verb $args } catch {|e| {ok: false, log: "", outcomes: [], error: $e.msg} }
            }
        }
    }
    let notes = $result.log | lines | where ($it | str trim | str starts-with $NOTE_PREFIX) | each { str trim | str replace $NOTE_PREFIX "" | str trim }
    $notes | each { log-debug $"note: ($m.id): ($in)" {kind: note} } | ignore
    $result | insert id $m.id | insert notes $notes | insert ms (since-ms $start)
}

# Its processes carry DOT_RUN_FILE and DOTFILES_MODULE, setsid'd ones included.
def module-procs-kill [id: string]: nothing -> nothing {
    let marks = [$"DOTFILES_MODULE=($id)" $"DOT_RUN_FILE=($env.DOT_RUN_FILE? | default '')"]
    let pids = glob /proc/[0-9]*/environ | each {|f|
        let environ = try { open --raw $f | decode utf-8 | split row (char nul) } catch { [] }
        if ($marks | all {|m| $m in $environ }) { $f | path dirname | path basename }
    } | compact | where $it != ($nu.pid | into string)
    if ($pids | is-not-empty) { ^kill -KILL ...$pids | complete | ignore }
}

# --timeout: a module still running is killed and counts as failed.
export def pipeline-apply [ctx: record, planned: table, verb: string, jobs: int, args: list = [], --timeout: duration]: nothing -> table {
    mut done = {}
    mut running = {}
    mut started = {}
    mut results = []
    mut pending = $planned
    let planned_ids = $planned.id
    # a timed-out module's marker: apply-module stops at its next action and the job sends nothing
    let cancel_dir = if $timeout == null { "" } else { mktemp --directory --tmpdir dot-cancel-XXXXXX }
    mut killed = false
    while ($pending | is-not-empty) or ($running | is-not-empty) {
        let finished = $done
        let busy = $running | columns | length
        let ready = $pending | where {|m| $m.after | all {|a| $a in $finished or $a not-in $planned_ids } }
        let serial_wait = $ready | where serial | is-not-empty
        # a serial module rewrites a whole shared file (~/.claude.json) without the lock, so it runs alone: while one is
        # running, start nothing, or a concurrent locked json-merge and its unlocked rewrite clobber each other
        let running_serial = $planned | where id in ($running | columns) | any {|m| $m.serial? | default false }
        let startable = if $running_serial { [] } else if $busy == 0 and $serial_wait { $ready | where serial | first 1 } else { $ready | where not serial | first ([($jobs - $busy) 0] | math max) }
        for m in $startable {
            let cancel = if $cancel_dir == "" { "" } else { $cancel_dir | path join ($m.id | str replace --all "/" "+") }
            let id = job spawn {
                # a job that dies without sending would leave job recv waiting forever
                let result = try { with-env {DOT_CANCEL_FILE: $cancel} { module-run $ctx $m $verb $args } } catch {|e|
                    {id: $m.id, ok: false, log: "", outcomes: [], error: $e.msg, notes: [], ms: 0}
                }
                if $cancel == "" or not ($cancel | path exists) { $result | job send 0 }
            }
            $running = $running | insert $m.id $id
            $started = $started | upsert $m.id (date now)
            $pending = $pending | where id != $m.id
        }
        if ($running | is-empty) {
            error make {msg: $"nothing can start: ($pending.id | str join ' ') wait for each other"}
        }
        let result = if $timeout == null { job recv } else {
            let since = $started
            let late = $running | columns | where {|id| (date now) - ($since | get $id) > $timeout } | get --optional 0
            if $late != null {
                touch ($cancel_dir | path join ($late | str replace --all "/" "+"))
                $killed = true
                try { job kill ($running | get $late) }
                module-procs-kill $late
                log-warn $"($late): ($verb) still running after ($timeout), killed" {module: $late}
                {id: $late, ok: false, log: "", outcomes: [], error: $"timed out after ($timeout)", notes: [], ms: ($timeout / 1ms)}
            } else {
                try { job recv --timeout 1sec } catch { null }
            }
        }
        # a late send from a module already given up on, or from an earlier call's killed job
        if $result == null or $result.id not-in ($running | columns) { continue }
        $running = $running | reject $result.id
        $done = $done | insert $result.id $result.ok
        $results = $results | append $result
        if not $result.ok and ($env.FAILURES_FILE? | is-not-empty) {
            fail $result.id
        }
        if ($result.log | str trim | is-not-empty) or not $result.ok {
            print $"--- ($result.id) \(($result.ms / 1000 | math round --precision 1)s\)"
            if ($result.log | str trim | is-not-empty) { print ($result.log | str trim --right) }
            if not $result.ok { print $"error: ($result.error)" }
        }
    }
    # a killed job may still be between actions and must keep seeing its marker
    if $cancel_dir != "" and not $killed { rm --recursive --force $cancel_dir }
    $results
}
