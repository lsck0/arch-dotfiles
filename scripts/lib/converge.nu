# Plan and apply for native modules; the per-verb records are the one record of what a module wrote.

use log.nu *
use state.nu [state-dir state-locked path-kind nu-bin save-atomic LIB_DIR SYSTEM_STATE]
use preserve.nu [sync-guard preserve-aside]
use json.nu [json-edits-apply]
use module.nu [DECL_KEYS DECL_KINDS unit-dir]
use ini.nu [ini-apply]
use cause.nu [cause-from-error cause-from-output cause-text argv-text]
use online.nu [network-online remote-pending OFFLINE_PENDING]

const OWN_LINK_PREFIXES = [$"($SYSTEM_STATE)/"]
# a step or exec past this is killed with its whole tree; a declaration's --timeout overrides it
export const STEP_TIMEOUT = 20min
# a --then is a restart or a reload
export const THEN_TIMEOUT = 5min

# The record of what a module's verb owns: <state>/modules/<id>/<verb>.nuon.
export def state-path [id: string, verb: string]: nothing -> path {
    state-dir | path join modules $id $"($verb).nuon"
}

export def state-read [id: string, verb: string]: nothing -> record {
    let file = state-path $id $verb
    if ($file | path exists) { open $file } else { {input: "", run: "", time: "", outputs: []} }
}

def assert-shape [value: record, keys: list<string>, what: string]: nothing -> nothing {
    if ($value | columns | sort) != ($keys | sort) {
        error make {msg: $"($what) has keys ($value | columns | str join ' '), wants ($keys | str join ' '): ($value | to nuon)"}
    }
}

# Rejects non-declarations before observing, so a bad one fails only its module.
export def decls-check [id: string, decls: list]: nothing -> nothing {
    for decl in $decls {
        if ($decl | describe) !~ '^record' { error make {msg: $"($id) declares ($decl | to nuon), not one declaration"} }
        assert-shape $decl $DECL_KEYS $"declaration of ($id)"
        if $decl.kind not-in $DECL_KINDS { error make {msg: $"($id) declares a ($decl.kind), not one of ($DECL_KINDS | str join ' ')"} }
        if ($decl.target | describe) != "string" { error make {msg: $"($id) declares a ($decl.kind) with target ($decl.target | to nuon), not a path"} }
    }
}

def sha [text: any]: nothing -> string {
    $text | hash sha256
}

export def unit-states [scope: string, units: list<string>]: nothing -> list<string> {
    # a unit systemd does not know answers on stderr only, so the batch falls back to asking each
    let batch = ^systemctl $"--($scope)" is-enabled ...$units | complete | get stdout | lines
    if ($batch | length) == ($units | length) { return $batch }
    $units | each {|u| ^systemctl $"--($scope)" is-enabled $u | complete | get stdout | str trim | if ($in | is-empty) { "not-found" } else { $in } }
}

# One external call for every path, its NUL-ended answers in order; an answer short (a path gone meanwhile) asks each.
export def ask-batch [paths: list<string>, batch: closure, each_path: closure]: nothing -> record {
    if ($paths | is-empty) { return {} }
    let run = do $batch $paths | complete
    let answers = $run.stdout | split row (char nul) | drop
    let got = if $run.exit_code == 0 and ($answers | length) == ($paths | length) { $answers } else { $paths | each {|p| do $each_path $p } }
    $paths | zip $got | reduce --fold {} {|a, acc| $acc | upsert $a.0 $a.1 }
}

# What is on disk now for each target (type, hash, link, mode) and each unit's enablement state; known: an earlier
# observation whose paths and units are taken as they are, only the rest looked at.
export def observe [targets: list<string>, units: list<string>, scope: string, known: record = {paths: {}, units: {}}]: nothing -> record {
    let kinds = $targets | uniq | where $it not-in $known.paths | each {|t| {target: $t, type: (path-kind $t)} }
    # one stat and one readlink for all, not one each: a plan observes a few thousand targets
    let files = $kinds | where type == file | get target
    let modes = ask-batch $files {|ps| ^stat --printf '%a\0' ...$ps } {|p| try { ^stat -c "%a" $p | str trim } catch { null } }
    let links = ask-batch ($kinds | where type == symlink | get target) {|ps| ^readlink -z ...$ps } {|p| ^readlink $p }
    let paths = $kinds | each {|k|
        {
            target: $k.target
            type: $k.type
            hash: (if $k.type == file { try { open --raw $k.target | sha $in } catch { "unreadable" } } else { null })
            link: ($links | get --optional $k.target)
            mode: ($modes | get --optional $k.target)
        }
    }
    let unit_names = $units | uniq | where $it not-in $known.units
    let states = if ($unit_names | is-empty) { [] } else {
        unit-states $scope $unit_names
    }
    {
        paths: ($paths | reduce --fold $known.paths {|p, acc| $acc | insert $p.target $p })
        units: ($unit_names | zip $states | reduce --fold $known.units {|u, acc| $acc | insert $u.0 $u.1 })
    }
}

# Newest write per path across all records, so one verb's merge onto another's file is no drift.
export def recorded-hashes []: nothing -> record {
    glob (state-dir | path join modules **/*.nuon) | each { open $in | get outputs } | flatten
    | where {|o| $o.kind in [file json ini] and ($o.hash? | default null) != null }
    | sort-by {|o| $o.at? | default 0 }
    | reduce --fold {} {|o, acc| $acc | upsert $o.target $o.hash }
}

def now-ns []: nothing -> int { date now | into int }

def out-key [kind: string, target: string]: nothing -> string { $"($kind)\t($target)" }

def own-link [link: string, repo: string]: nothing -> bool {
    ($link | str starts-with $"($repo)/") or ($OWN_LINK_PREFIXES | any {|p| $link | str starts-with $p })
}

def action [module: string, kind: string, target: string, reason: string, decl: any, before: any, after: any]: nothing -> record {
    {module: $module, kind: $kind, target: $target, reason: $reason, decl: $decl, before: $before, after: $after}
}

# Folds merge decls on one file into one, else each would plan against the file on disk and the last wins.
# A --then is one command, so a fold takes at most one distinct --then.
def fold-merges [decls: list<record>]: nothing -> list<record> {
    let dup = $decls | where kind in [json ini] | group-by target | items {|t, g| if ($g | length) > 1 { $t } } | compact
    if ($dup | is-empty) { return $decls }
    let first = $decls | enumerate | where item.kind in [json ini] and item.target in $dup | group-by {|r| $r.item.target } | items {|_, g| $g.0.index }
    $decls | enumerate | each {|r|
        let d = $r.item
        if $d.kind not-in [json ini] or $d.target not-in $dup { return $d }
        if $r.index not-in $first { return null }
        let g = $decls | where kind in [json ini] and target == $d.target
        let thens = $g | get then | where { is-not-empty } | uniq
        if ($thens | length) > 1 { error make {msg: $"($d.target): merges with different --then, one file runs one: ($thens | to nuon)"} }
        $d | update edits ($g | each { $in.edits } | flatten) | update then ($thens | get --optional 0 | default [])
    } | compact
}

export def mode-normal [mode: any]: nothing -> any {
    if $mode == null { null } else { $mode | str trim --left --char "0" }
}

def link-stale [obs: record, target: string, repo: string]: nothing -> bool {
    $obs.type == symlink and ((own-link $obs.link $repo) or not ($target | path exists))
}

# What an apply does to a declared file: obs on disk, want the content's hash, recorded the hash it last wrote.
def file-classify [obs: record, want: string, recorded: any, generated: bool, stale_link: bool, force: bool, mode: any = null]: nothing -> record {
    let c = {|kind, reason, preserve| {kind: $kind, reason: $reason, preserve: $preserve} }
    if $obs.type == "" {
        do $c create "missing" false
    } else if $stale_link {
        do $c update "a link of the old linked form" false
    } else if $obs.type == file and $obs.hash == $want {
        if $mode != null and (mode-normal ($obs.mode? | default $mode)) != (mode-normal $mode) {
            do $c update "mode changed" false
        } else if $recorded == $want { do $c skip "" false } else { do $c record "already this content" false }
    } else if $obs.type == file and ($generated or $recorded == $obs.hash) {
        do $c update "changed in the module" false
    } else if $recorded == null {
        do $c update "not the dotfiles' own yet: preserved aside" true
    } else if $force {
        do $c update "drift, forced: preserved aside" true
    } else {
        do $c drift "changed since the last apply" false
    }
}

# A recorded output's state without evaluating its module: changed, missing or null.
export def output-file-state [output: record, obs: record, repo: string, written: any = null]: nothing -> any {
    if $written != null and $obs.hash? == $written { return null }
    let c = file-classify $obs $output.hash $output.hash ($output.generated? | default false) (link-stale $obs $output.target $repo) false
    match $c.kind { "drift" => "changed", "create" => "missing", _ => null }
}

def merge-read [obs: record, target: string]: nothing -> string {
    if $obs.type? not-in [file symlink] { return "" }
    try { open --raw $target } catch { "" }
}

# Declarations against disk, then orphans (removals and disables first).
export def plan-module [id: string, decls: list<record>, prev: list<record>, seen: record, recorded: record, repo: string, force: bool, all_targets: list<string> = []]: nothing -> list<record> {
    let wanted = (fold-merges $decls) | each {|d|
        let obs = $seen.paths | get --optional $d.target
        if $obs.hash? == "unreadable" { return (action $id unreadable $d.target "unreadable as this user, checked at apply" $d null null) }
        let then_failed = ($d.then | is-not-empty) and ($prev | where kind == $d.kind and target == $d.target | get --optional 0.then_failed | default false)
        match $d.kind {
            "file" => {
                let want = if $d.content != null { sha $d.content } else { open --raw $d.source | sha $in }
                let written = $recorded | get --optional $d.target
                let rec = if $written != null and $obs.hash? == $written { $written } else {
                    $prev | where kind == file and target == $d.target | get --optional 0.hash | default $written
                }
                let c = file-classify $obs $want $rec $d.generated (link-stale $obs $d.target $repo) $force $d.mode
                let before = match $obs.type { "" => null, "symlink" => $obs.link, _ => $obs.hash }
                action $id $c.kind $d.target $c.reason (if $c.preserve { $d | insert preserve true } else { $d }) $before $want
            }
            "link" => {
                if $obs.type == symlink and $obs.link == $d.source {
                    action $id skip $d.target "" $d $obs.link $d.source
                } else if $obs.type == "" or (link-stale $obs $d.target $repo) {
                    action $id create $d.target "missing" $d $obs.link $d.source
                } else if $obs.type == file and ($d.source | path exists) and $obs.hash == (open --raw $d.source | sha $in) {
                    action $id update $d.target "a copy of the source" $d $obs.hash $d.source
                } else if $obs.type == file and ($prev | where kind == file and target == $d.target | get --optional 0.hash) == $obs.hash {
                    action $id update $d.target "a copy the dotfiles wrote" ($d | insert preserve true) $obs.hash $d.source
                } else if $obs.type == file and $d.target not-in ($prev | where kind in [file link] | get target) {
                    action $id update $d.target "not the dotfiles' own yet: preserved aside" ($d | insert preserve true) $obs.hash $d.source
                } else if $force {
                    action $id update $d.target "drift, forced: preserved aside" ($d | insert preserve true) $obs.hash $d.source
                } else {
                    action $id drift $d.target "not the dotfiles' own" $d $obs.hash $d.source
                }
            }
            "json" => {
                let raw = merge-read $obs $d.target
                let current = if ($raw | str trim | is-empty) { {} } else { try { $raw | from json } catch { null } }
                if $current == null { return (action $id merge $d.target "not valid json now, read again at apply" $d $obs.hash? null) }
                let merged = $current | json-edits-apply $d.edits
                if $then_failed { action $id merge $d.target "its --then failed last time" $d $obs.hash null
                } else if $merged == $current and ($raw | is-not-empty) { action $id skip $d.target "" $d null null } else { action $id merge $d.target "keys differ" $d $obs.hash null }
            }
            "ini" => {
                let raw = merge-read $obs $d.target
                let merged = $d.edits | reduce --fold $raw {|e, text| $text | ini-apply $e.values $e.missing_only }
                if $merged == $raw and not $then_failed { action $id skip $d.target "" $d null null } else {
                    action $id merge $d.target (if $merged == $raw { "its --then failed last time" } else { "keys differ" }) ($d | update content $merged) $obs.hash null
                }
            }
            "unit" => {
                let state = $seen.units | get --optional $d.target | default "not-found"
                let verb = match $d.state { "enabled" => "enable", "disabled" => "disable", "masked" => "mask" }
                let done = match $d.state { "disabled" => ($state != "enabled"), _ => ($state == $d.state) }
                if $done { action $id skip $d.target "" $d $state $state } else { action $id $verb $d.target $state $d $state $d.state }
            }
            "exec" => {
                if $d.creates != null and ($d.creates | path exists) { action $id skip $d.target "" $d null null } else { action $id exec $d.target "" $d null null }
            }
            "step" => (action $id step $d.target "" $d null null)
        }
    }
    let targets = $decls.target
    let orphans = $prev | where target not-in $targets | each {|o|
        let obs = $seen.paths | get --optional $o.target | default {type: "", hash: null, link: null}
        let claimed = $o.target in $all_targets
        match $o.kind {
            "file" => {
                if $claimed { action $id forget $o.target "now declared by another module" $o null null
                } else if $obs.type == "" { action $id forget $o.target "already gone" $o null null
                } else if $obs.hash == $o.hash { action $id remove $o.target "no longer declared" $o $o.hash null
                } else { action $id drift $o.target "no longer declared, changed since: left in place" $o $obs.hash null }
            }
            "link" => {
                if $claimed { action $id forget $o.target "now declared by another module" $o null null
                } else if $obs.type == symlink and $obs.link == $o.source { action $id remove $o.target "no longer declared" $o $o.source null } else { action $id forget $o.target "not the link it was" $o null null }
            }
            "unit" => (if $claimed { action $id forget $o.target "now declared by another module" $o null null } else { match ($o.state? | default enabled) {
                "enabled" => (action $id disable $o.target "no longer declared" ($o | insert now true) enabled null)
                "masked" => (action $id unmask $o.target "no longer declared" $o masked null)
                _ => (action $id forget $o.target "no longer declared" $o null null)
            } })
            _ => null
        }
    } | compact
    $wanted ++ ($orphans | sort-by {|a| if $a.kind in [disable unmask] { 0 } else { 1 } })
}

# Removes emptied parent dirs; stops at a non-empty dir, a link, home or a dir a package owns.
def prune-parents [start: path]: nothing -> nothing {
    mut dir = $start
    while $dir != $nu.home-dir and $dir != "/" and (path-kind $dir) == "dir" and (try { ls --all $dir | is-empty } catch { false }) {
        if (^pacman -Qo $dir | complete).exit_code == 0 { break }
        try { rm $dir } catch { break }
        $dir = $dir | path dirname
    }
}

def write-file [a: record]: nothing -> nothing {
    let d = $a.decl
    mkdir ($d.target | path dirname)
    # the pid in the name: a second run writing the same target must not take over a half-written temp
    let tmp = $"($d.target).dot-new.($nu.pid)"
    if (path-kind $tmp) != "" { rm $tmp }
    # 600 before any content: save and cp keep an existing file's mode, so a secret never sits umask-readable
    ^install -m 600 /dev/null $tmp
    if $d.content != null { $d.content | save --force --raw $tmp } else { ^cp $d.source $tmp }
    ^chmod $d.mode $tmp
    if ($d.inplace? | default false) and (path-kind $d.target) == "file" {
        ^chmod $d.mode $d.target
        ^cp $tmp $d.target
        rm $tmp
    } else {
        ^mv -fT $tmp $d.target
    }
}

def home-short []: path -> string {
    let file = $in
    let home = $nu.home-dir
    if ($file | str starts-with $"($home)/") { $"~/($file | path relative-to $home)" } else { $file }
}

# A command of an action, bounded by timeout: a failure carries its cause, a timeout says so.
def action-command [a: record, dir: path, what: string, argv: list<string>, timeout: duration]: nothing -> string {
    let out = do { cd $dir; command-stream $"($a.module) ($a.target)" $argv $timeout }
    if $out.timed_out { error make {msg: $"`($what)` timed out after ($timeout)"} }
    if $out.exit_code != 0 { error make {msg: (cause-text (cause-from-output $what $out.exit_code $out.output))} }
    $out.output
}

# nu -c ends on a failed external with its exit code alone: the step prints the error, its call and line, itself.
def run-step [a: record, dir: path]: nothing -> string {
    let call = $"use ($dir | to nuon) [($a.target)]; try { ($a.target) ($a.decl.argv | each { to nuon } | str join ' ') } catch {|e| print -e $e.rendered; exit \($e.exit_code? | default 1\) }"
    action-command $a $dir $"step ($a.target)" [(nu-bin) --no-config-file -I $LIB_DIR -c $call] ($a.decl.timeout? | default $STEP_TIMEOUT)
}

# a sibling module's daemon-reload running at the same moment fails a unit verb once
def systemctl-retry [scope: string, ...args: string]: nothing -> nothing {
    if (do { ^systemctl $"--($scope)" ...$args } | complete).exit_code != 0 {
        sleep 1sec
        ^systemctl $"--($scope)" ...$args
    }
}

# A failed --then keeps the old hash, so the next apply runs it again; a merge's record carries then_failed instead.
def run-then [a: record, dir: path]: nothing -> string {
    if ($a.decl.then | is-empty) { return "" }
    action-command $a $dir (argv-text $a.decl.then) $a.decl.then $THEN_TIMEOUT
}

def run-exec [a: record, dir: path]: nothing -> string {
    action-command $a $dir (argv-text $a.decl.argv) $a.decl.argv ($a.decl.timeout? | default $STEP_TIMEOUT)
}

# One outcome per action; a failure stays with its action.
export def apply-module [actions: list<record>, dir: path, scope: string]: nothing -> list<record> {
    let unreadable = $actions | where kind == unreadable | each {|a|
        log-record "ERROR" $"unreadable ($a.target)" {module: $a.module, kind: $a.kind, target: $a.target, ms: 0, outcome: $a.reason}
        $a | merge {ok: false, pending: null, error: $a.reason, aside: null, output: "", hash: null, at: null} | insert ms 0
    }
    # new files before changed ones: a live reader never sees a reference to a missing file
    let file_write = {|a| $a.kind in [create update] and $a.decl.kind? != "link" }
    let hooked = {|a| $a.decl.then? | default [] | is-not-empty }
    let ordered = $actions | where kind not-in [skip drift unreadable] | chunk-by $file_write
        | each {|run|
            if not (do $file_write $run.0) { $run } else {
                let plain = $run | where {|a| not (do $hooked $a) }
                # a write with a --then (a restart) goes last, after every file of its run it may need
                ($plain | where kind == create) ++ ($plain | where kind == update) ++ ($run | where {|a| do $hooked $a })
            }
        }
        | flatten
    # pipeline-apply's --timeout cancels a module through this marker: a killed job's try would otherwise go on
    let cancel = $env.DOT_CANCEL_FILE? | default ""
    let recorded = if ($ordered | any { $in.kind == "merge" }) { recorded-hashes } else { {} }
    let run = $ordered | reduce --fold {written: $recorded, outcomes: []} {|a, acc|
        let start = date now
        let result = if $cancel != "" and ($cancel | path exists) {
            {ok: false, pending: null, error: "cancelled, the module timed out", aside: null, output: "", hash: null, at: null}
        } else if $a.kind in [exec step] and $a.decl.requires? != null and not ($a.decl.requires | path exists) {
            {ok: true, pending: $"waits on ($a.decl.requires | home-short), not there yet", error: null, aside: null, output: "", hash: null, at: null}
        } else if $a.kind in [exec step] and $a.decl.network? == true and not (network-online) {
            {ok: true, pending: $OFFLINE_PENDING, error: null, aside: null, output: "", hash: null, at: null}
        } else { try {
            match $a.kind {
                "create" | "update" => {
                    sync-guard $a.target
                    let aside = if ($a.decl.preserve? | default false) { preserve-aside $a.target } else { null }
                    if $a.decl.kind == "link" {
                        mkdir ($a.target | path dirname)
                        if (path-kind $a.target) == file { rm --force $a.target }
                        ^ln -sfnT $a.decl.source $a.target
                    } else {
                        write-file $a
                    }
                    let at = now-ns
                    # a --then (a restart) and every later step must see the new unit file or drop-in
                    if ($a.target | str starts-with (unit-dir)) { systemctl-retry $scope daemon-reload }
                    {aside: $aside, output: (run-then $a $dir), hash: (if $a.decl.kind == "link" { null } else { $a.after }), at: $at}
                }
                "record" => { {output: (run-then $a $dir), hash: $a.after, at: (now-ns)} }
                "merge" => {
                    sync-guard $a.target
                    mkdir ($a.target | path dirname)
                    let last = $acc.written | get --optional $a.target
                    let lock = $"(state-dir)/json.lock"
                    let out = if $a.decl.kind == "ini" {
                        state-locked $lock ini-update {file: $a.target, edits: $a.decl.edits} | complete
                    } else {
                        state-locked $lock json-update {file: $a.target, edits: $a.decl.edits, recorded_sum: ($last | default "")} | complete
                    }
                    if $out.exit_code != 0 { error make {msg: $"($a.decl.kind) merge exited ($out.exit_code): (error-brief $out.stderr)"} }
                    let owned = ($out.stdout | str contains owned) or ($a.decl.kind == "ini" and $a.before != null and $a.before == $last and ($out.stdout | str contains changed))
                    let output = run-then $a $dir
                    if $owned { {output: $output, hash: (open --raw $a.target | sha $in), at: (now-ns)} } else { {output: $output} }
                }
                "disable" => {
                    systemctl-retry $scope disable $a.target
                    # best effort: a stock unit with RefuseManualStop= refuses it, and the disable already happened
                    if ($a.decl.now? | default false) { do { ^systemctl $"--($scope)" stop $a.target } | complete | ignore }
                    {}
                }
                "enable" | "mask" => {
                    let now = if ($a.decl.now? | default false) { [--now] } else { [] }
                    systemctl-retry $scope $a.kind ...$now $a.target
                    {}
                }
                "unmask" => { systemctl-retry $scope unmask $a.target; {} }
                "step" => { {output: (run-step $a $dir)} }
                "remove" => {
                    let current = if (path-kind $a.target) == file { open --raw $a.target | sha $in } else { null }
                    if $a.decl.kind == "file" and $current != $a.before {
                        {}
                    } else {
                        rm --force $a.target
                        prune-parents ($a.target | path dirname)
                        if ($a.decl.aside? | default null) != null and ($a.decl.aside | path exists) { ^mv -n $a.decl.aside $a.target }
                        {}
                    }
                }
                "forget" => { {} }
                "exec" => { {output: (run-exec $a $dir)} }
            }
            | {ok: true, pending: null, error: null, aside: ($in.aside? | default null), output: ($in.output? | default ""), hash: ($in.hash? | default null), at: ($in.at? | default null)}
        } catch {|e|
            let error = cause-text (cause-from-error $e)
            let remote = if $a.kind in [exec step] and $a.decl.network? == true { remote-pending $error } else { null }
            if $remote != null { {ok: true, pending: $remote, error: null, aside: null, output: "", hash: null, at: null} } else {
                {ok: false, pending: null, error: $error, aside: null, output: "", hash: null, at: null}
            }
        } }
        let ms = since-ms $start
        let outcome = if not $result.ok { $result.error } else if $result.pending != null { $"pending, ($result.pending)" } else { "ok" }
        log-record (if $result.ok { "DEBUG" } else { "ERROR" }) $"($a.kind) ($a.target)" {module: $a.module, kind: $a.kind, target: $a.target, ms: $ms, outcome: $outcome}
        {
            written: (if $result.hash != null { $acc.written | upsert $a.target $result.hash } else { $acc.written })
            outcomes: ($acc.outcomes | append ($a | merge $result | insert ms $ms))
        }
    }
    let outcomes = $run.outcomes
    let unit_root = unit-dir
    # a create or update under unit_root already reloaded right after its write
    if ($outcomes | any {|o| $o.ok and $o.kind not-in [create update] and ($o.target | str starts-with $unit_root) }) {
        ^systemctl $"--($scope)" daemon-reload
    }
    $outcomes ++ $unreadable
}

# A failed action keeps its previous output and clears the input hash, so it is planned again; a pending one (offline)
# did not run, so it is no output either.
export def state-write [id: string, verb: string, input: string, actions: list<record>, outcomes: list<record>, prev: list<record>]: nothing -> nothing {
    let done = $outcomes | where {|o| $o.ok and $o.pending? == null } | reduce --fold {} {|o, acc| $acc | upsert (out-key $o.decl.kind $o.target) $o }
    let failed = $outcomes | where not ok | get target
    let kept = {|a| ($a.decl.kind == "exec" and $a.decl.creates? != null and $a.kind in [skip exec]) or ($a.decl.kind in [file link unit] and $a.kind not-in [remove forget unmask] and not ($a.kind == "disable" and $a.decl.state? != "disabled")) or ($a.decl.kind in [json ini] and $a.kind in [merge skip]) }
    let owned = $actions | where {|a| do $kept $a } | each {|a|
        let before = $prev | where kind == $a.decl.kind and target == $a.target | get --optional 0
        let o = $done | get --optional (out-key $a.decl.kind $a.target)
        if $a.decl.kind in [json ini] {
            let output = if $o.hash? != null { {kind: $a.decl.kind, target: $a.target, hash: $o.hash, at: $o.at} } else { $before }
            # the merge may have landed before its --then failed: plan-module merges again until the --then ran
            if $a.target in $failed and ($a.decl.then | is-not-empty) {
                $output | default {kind: $a.decl.kind, target: $a.target, hash: null, at: null} | upsert then_failed true
            } else if $output != null { $output | reject --optional then_failed } else { null }
        } else if $a.kind == "skip" or $o != null {
            {
                kind: $a.decl.kind
                target: $a.target
                hash: (if $a.decl.kind == "file" { $a.after } else { null })
                mode: (if $a.decl.kind == "file" { $a.decl.mode? } else { null })
                generated: ($a.decl.generated? | default false)
                source: (if $a.decl.kind == "exec" { $a.decl.creates } else { $a.decl.source })
                state: $a.decl.state?
                aside: ($o.aside? | default ($before.aside? | default null))
                at: (if $a.decl.kind != "file" { null } else { $o.at? | default ($before.at? | default 0) })
            }
        } else {
            $before
        }
    } | compact
    let file = state-path $id $verb
    mkdir ($file | path dirname)
    {
        input: (if ($failed | is-empty) { $input } else { "" })
        run: ($env.DOT_RUN_ID? | default "")
        time: (date now | format date "%+")
        outputs: ($owned ++ ($prev | where target in $failed and target not-in $owned.target))
    } | to nuon | save-atomic $file
}
