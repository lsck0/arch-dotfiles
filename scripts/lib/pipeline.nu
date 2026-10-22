# One layer's run: load platform, profile, modules and options, plan every module (skipping those whose
# inputs and outputs are unchanged), then apply them in dependency order as parallel jobs.

use log.nu *
use state.nu [LIB_DIR]
use platform.nu [platform-load platform-env]
use profile.nu [profile-load]
use options.nu [options-resolve]
use modules.nu [modules-discover modules-graph modules-eval]
use converge.nu [state-read observe recorded-hashes decls-check plan-module apply-module state-write]
use secrets.nu [secret-is-plaintext]

const HASH_STAMP = '%P %s %T@\n'
const EXEC_PASSES_MAX = 3
const NOTE_PREFIX = "note:"
const REVERT_VERBS = [link system]
# a link's source can be a live mount (autofs, a network share): bound the existence probe so one
# unreachable host doesn't stall every plan/apply; a timeout counts as "gone", same as a real miss
const LINK_PROBE_TIMEOUT_S = 2

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

# The run context for a layer: repo, platform, profile and every discovered module with its resolved options.
export def --env pipeline-load [repo: path, layer: string]: nothing -> record {
    $env.DOT_LAYER = $layer
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
    ^find $dir -type f -not -name '*.log' -printf $HASH_STAMP | lines | sort | str join "\n"
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
            "file" => ($obs.hash? == $o.hash)
            "link" => ($obs.link? == $o.source)
            "exec" => ($o.source | path exists)
            "unit" => (match ($o.state? | default enabled) { "disabled" => (($seen.units | get --optional $o.target) != "enabled"), $s => (($seen.units | get --optional $o.target) == $s) })
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

# One row per module in run order with its planned actions; a module with unchanged inputs and clean
# outputs is skipped unevaluated, a module turned off plans the removal of what it installed.
export def pipeline-plan [ctx: record, verb: string, ids: list<string>, force: bool, args: list = []]: nothing -> table {
    let unknown = $ids | where $it not-in $ctx.modules.id
    if ($unknown | is-not-empty) {
        error make {msg: $"no module ($unknown | str join ', '); dot plan --modules lists them"}
    }
    let broken = $ctx.modules | where broken and ($ids | is-empty) or $it.id in $ids | where broken
    if ($ids | is-not-empty) and ($broken | is-not-empty) {
        error make {msg: $"($broken.id | str join ', '): mod.nu does not parse"}
    }
    let active = $ctx.modules | where {|m| $verb in $m.verbs and $m.cfg.enable and (($ids | is-empty) or $m.id in $ids) }
    let retired = if $verb not-in $REVERT_VERBS { [] } else {
        $ctx.modules | where {|m| not $m.cfg.enable and not $m.broken and $verb in $m.native and (($ids | is-empty) or $m.id in $ids) and ((state-read $m.id $verb).outputs | is-not-empty) }
    }
    let graph = span graph {} { modules-graph $ctx.repo ($active ++ $retired) }
    let global = [
        (stamp $LIB_DIR) ($ctx.platform.facts | to nuon) ($ctx.profile.capabilities? | default [] | to nuon)
        (secret-is-plaintext ($ctx.repo | path join configs secrets keys pgp_privatekey.asc)) $verb ($args | to nuon)
    ] | str join "\n"
    let natives = $graph | where $verb in $it.native | each {|m|
        let prev = state-read $m.id $verb
        let outside = $prev.outputs | where kind in [file link] and source != null and not ($it.source | str starts-with $m.dir)
        # a link depends only on its source being there: a linked live app dir's mtime moves all day; the
        # source can be an unreachable network mount, so bound the probe (LINK_PROBE_TIMEOUT_S) instead of
        # a bare `path exists`, whose stat() can block for a kernel TCP-connect timeout on a dead autofs mount
        let links = $outside | where kind == link | get source
            | each {|s| $"($s) ((do { ^timeout $LINK_PROBE_TIMEOUT_S test -e $s } | complete).exit_code == 0)" }
            | str join "\n"
        let input = [$global (stamp $m.dir) ($m.cfg | to nuon) (stat $ctx.repo ($m.meta.inputs? | default [])) (stat $ctx.repo ($outside | where kind == file | get source)) $links] | str join "\n" | hash sha256
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
        let row = {id: $m.id, dir: $m.dir, after: $m.after, level: $m.level, serial: $m.meta.serial, cfg: $m.cfg, options: $m.options}
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
        let again = eval-plan $ctx [$m] $verb $args {$m.id: $outputs} false | first
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

# Runs the planned modules as jobs, each once its after list finished, at most jobs at once, a serial one alone.
export def pipeline-apply [ctx: record, planned: table, verb: string, jobs: int, args: list = []]: nothing -> table {
    mut done = {}
    mut running = {}
    mut results = []
    mut pending = $planned
    let planned_ids = $planned.id
    while ($pending | is-not-empty) or ($running | is-not-empty) {
        let finished = $done
        let busy = $running | columns | length
        let ready = $pending | where {|m| $m.after | all {|a| $a in $finished or $a not-in $planned_ids } }
        let serial_wait = $ready | where serial | is-not-empty
        let startable = if $busy == 0 and $serial_wait { $ready | where serial | first 1 } else { $ready | where not serial | first ([($jobs - $busy) 0] | math max) }
        for m in $startable {
            let id = job spawn { module-run $ctx $m $verb $args | job send 0 }
            $running = $running | insert $m.id $id
            $pending = $pending | where id != $m.id
        }
        if ($running | is-empty) {
            error make {msg: $"nothing can start: ($pending.id | str join ' ') wait for each other"}
        }
        let result = job recv
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
    $results
}
