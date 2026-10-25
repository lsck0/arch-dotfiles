# Plan and apply for native modules: observes each declared target, classifies it against what dot last
# wrote (create, update, skip, drift, merge, remove), applies the actions and records the outputs per verb.

use log.nu *
use state.nu [state-dir state-locked path-kind nu-bin save-atomic LIB_DIR SYSTEM_STATE]
use written.nu [sync-guard preserve-aside written-file written-record written-forget]
use json.nu [json-edits-apply]
use module.nu [DECL_KEYS DECL_KINDS unit-dir]
use ini.nu [ini-apply]

const OWN_LINK_PREFIXES = [$"($SYSTEM_STATE)/"]

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

# Fails on anything not a declaration before any target is observed, so a malformed one fails this module
# and not the whole layer.
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

# What is on disk now for each target (type, hash, link) and each unit's enablement state.
export def observe [targets: list<string>, units: list<string>, scope: string]: nothing -> record {
    let paths = $targets | uniq | each {|t|
        let type = path-kind $t
        {
            target: $t
            type: $type
            hash: (if $type == file { try { open --raw $t | sha $in } catch { "unreadable" } } else { null })
            link: (if $type == symlink { ^readlink $t } else { null })
            mode: (if $type == file { try { ^stat -c "%a" $t | str trim } catch { null } } else { null })
        }
    }
    let unit_names = $units | uniq
    let states = if ($unit_names | is-empty) { [] } else {
        unit-states $scope $unit_names
    }
    {
        paths: ($paths | reduce --fold {} {|p, acc| $acc | insert $p.target $p })
        units: ($unit_names | zip $states | reduce --fold {} {|u, acc| $acc | insert $u.0 $u.1 })
    }
}

# The hash dot last wrote per path, from the written file.
export def recorded-hashes []: nothing -> record {
    let file = written-file
    if not ($file | path exists) { return {} }
    open --raw $file | lines | where $it != "" | split column "\t" path sum
    | reduce --fold {} {|row, acc| $acc | upsert $row.path $row.sum }
}

def own-link [link: string, repo: string]: nothing -> bool {
    ($link | str starts-with $"($repo)/") or ($OWN_LINK_PREFIXES | any {|p| $link | str starts-with $p })
}

def action [module: string, kind: string, target: string, reason: string, decl: any, before: any, after: any]: nothing -> record {
    {module: $module, kind: $kind, target: $target, reason: $reason, decl: $decl, before: $before, after: $after}
}

# Folds merge decls on one file into one, else each would plan against the file on disk and the last wins.
def fold-merges [decls: list<record>]: nothing -> list<record> {
    let dup = $decls | where kind in [json ini] | group-by target | items {|t, g| if ($g | length) > 1 { $t } } | compact
    if ($dup | is-empty) { return $decls }
    let first = $decls | enumerate | where item.kind in [json ini] and item.target in $dup | group-by {|r| $r.item.target } | items {|_, g| $g.0.index }
    $decls | enumerate | each {|r|
        let d = $r.item
        if $d.kind not-in [json ini] or $d.target not-in $dup { return $d }
        if $r.index not-in $first { return null }
        let g = $decls | where kind in [json ini] and target == $d.target
        $d | update edits ($g | each { $in.edits } | flatten) | update then ($g | each { $in.then } | flatten | uniq)
    } | compact
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
        if $mode != null and ($obs.mode? | default $mode) != $mode {
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

# A recorded output as the next apply sees it, without evaluating its module: changed, missing or null;
# written is the hash dot last wrote there, so another verb's merge onto it is no drift.
export def output-file-state [output: record, obs: record, repo: string, written: any = null]: nothing -> any {
    if $written != null and $obs.hash? == $written { return null }
    let c = file-classify $obs $output.hash $output.hash ($output.generated? | default false) (link-stale $obs $output.target $repo) false
    match $c.kind { "drift" => "changed", "create" => "missing", _ => null }
}

def merge-read [obs: record, target: string]: nothing -> string {
    if $obs.type? not-in [file symlink] { return "" }
    try { open --raw $target } catch { "" }
}

# The actions for one module: its declarations against what is on disk, then its orphaned outputs
# (removals and disables, sorted first).
export def plan-module [id: string, decls: list<record>, prev: list<record>, seen: record, recorded: record, repo: string, force: bool, all_targets: list<string> = []]: nothing -> list<record> {
    let wanted = (fold-merges $decls) | each {|d|
        let obs = $seen.paths | get --optional $d.target
        if $obs.hash? == "unreadable" { return (action $id unreadable $d.target "unreadable as this user, checked at apply" $d null null) }
        match $d.kind {
            "file" => {
                let want = if $d.content != null { sha $d.content } else { open --raw $d.source | sha $in }
                let written = $recorded | get --optional $d.target
                let rec = if $written != null and $obs.hash? == $written { $written } else {
                    $prev | where target == $d.target | get --optional 0.hash | default $written
                }
                let c = file-classify $obs $want $rec $d.generated (link-stale $obs $d.target $repo) $force $d.mode
                let before = match $obs.type { "" => null, "symlink" => $obs.link, _ => $obs.hash }
                action $id $c.kind $d.target $c.reason (if $c.preserve { $d | insert preserve true } else { $d }) $before $want
            }
            "link" => {
                if $obs.type == symlink and $obs.link == $d.source {
                    action $id skip $d.target "" $d $obs.link $d.source
                } else if $obs.type == "" or ($obs.type == symlink and ((own-link $obs.link $repo) or not ($d.target | path exists))) {
                    action $id create $d.target "missing" $d $obs.link $d.source
                } else if $obs.type == file and ($d.source | path exists) and $obs.hash == (open --raw $d.source | sha $in) {
                    action $id update $d.target "a copy of the source" $d $obs.hash $d.source
                } else if $obs.type == file and ($prev | where target == $d.target | get --optional 0.hash) == $obs.hash {
                    action $id update $d.target "a copy the dotfiles wrote" ($d | insert preserve true) $obs.hash $d.source
                } else if $obs.type == file and $d.target not-in $prev.target {
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
                if $merged == $current and ($raw | is-not-empty) { action $id skip $d.target "" $d null null } else { action $id merge $d.target "keys differ" $d $obs.hash null }
            }
            "ini" => {
                let raw = merge-read $obs $d.target
                let merged = $d.edits | reduce --fold $raw {|e, text| $text | ini-apply $e.values $e.missing_only }
                if $merged == $raw { action $id skip $d.target "" $d null null } else { action $id merge $d.target "keys differ" ($d | update content $merged) $obs.hash null }
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
    if (path-kind $tmp) == "symlink" { rm $tmp }
    if $d.content != null { $d.content | save --force --raw $tmp } else { ^cp $d.source $tmp }
    ^chmod $d.mode $tmp
    if ($d.inplace? | default false) and (path-kind $d.target) == "file" {
        ^cp $tmp $d.target
        rm $tmp
    } else {
        ^mv -fT $tmp $d.target
    }
    written-record $d.target
}

def run-step [a: record, dir: path]: nothing -> string {
    let call = $"use ($dir | to nuon) [($a.target)]; ($a.target) ($a.decl.argv | each { to nuon } | str join ' ')"
    let out = do { cd $dir; command-stream $"($a.module) ($a.target)" [(nu-bin) --no-config-file -I $LIB_DIR -c $call] }
    if $out.exit_code != 0 {
        error make {msg: $"step ($a.target) exited ($out.exit_code): ($out.tail)"}
    }
    $out.output
}

# a sibling module's daemon-reload running at the same moment fails a unit verb once
def systemctl-retry [scope: string, ...args: string]: nothing -> nothing {
    if (do { ^systemctl $"--($scope)" ...$args } | complete).exit_code != 0 {
        sleep 1sec
        ^systemctl $"--($scope)" ...$args
    }
}

# A failed --then forgets the file, so the next apply records it again and runs the --then once more.
def run-then [a: record, dir: path]: nothing -> string {
    if ($a.decl.then | is-empty) { return "" }
    try { run-exec ($a | update decl.argv $a.decl.then) $dir } catch {|e|
        if $a.decl.kind == "file" { written-forget $a.target }
        error make {msg: $e.msg}
    }
}

def run-exec [a: record, dir: path]: nothing -> string {
    let out = do { cd $dir; command-stream $"($a.module) ($a.target)" $a.decl.argv }
    if $out.exit_code != 0 {
        error make {msg: $"($a.target) exited ($out.exit_code): ($out.tail)"}
    }
    $out.output
}

# Runs a module's planned actions; one outcome per action, a failure confined to that action.
export def apply-module [actions: list<record>, dir: path, scope: string]: nothing -> list<record> {
    let unreadable = $actions | where kind == unreadable | each {|a|
        log-record "ERROR" $"unreadable ($a.target)" {module: $a.module, kind: $a.kind, target: $a.target, ms: 0, outcome: $a.reason}
        $a | merge {ok: false, error: $a.reason, aside: null, output: ""} | insert ms 0
    }
    # within a run of file writes, the new files land before the changed ones: a live reader (quickshell's
    # qmldir) never sees a reference to a file not there yet
    let file_write = {|a| $a.kind in [create update] and $a.decl.kind? != "link" }
    let ordered = $actions | where kind not-in [skip drift unreadable] | chunk-by $file_write
        | each {|run| if (do $file_write $run.0) { ($run | where kind == create) ++ ($run | where kind == update) } else { $run } }
        | flatten
    let outcomes = $ordered | each {|a|
        let start = date now
        let result = try {
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
                    # a --then (a restart) and every later step must see the new unit file or drop-in
                    if ($a.target | str starts-with (unit-dir)) { ^systemctl $"--($scope)" daemon-reload }
                    {aside: $aside, output: (run-then $a $dir)}
                }
                "record" => { written-record $a.target; {output: (run-then $a $dir)} }
                "merge" => {
                    sync-guard $a.target
                    mkdir ($a.target | path dirname)
                    let out = if $a.decl.kind == "ini" {
                        state-locked $"(state-dir)/json.lock" ini-update {file: $a.target, edits: $a.decl.edits} | complete
                    } else {
                        let recorded = recorded-hashes | get --optional $a.target | default ""
                        state-locked $"(state-dir)/json.lock" json-update {file: $a.target, edits: $a.decl.edits, recorded_sum: $recorded} | complete
                    }
                    if $out.exit_code != 0 { error make {msg: $"($a.decl.kind) merge exited ($out.exit_code): (error-brief $out.stderr)"} }
                    let owned = $a.decl.kind == "ini" and $a.before != null and $a.before == (recorded-hashes | get --optional $a.target)
                    if ($out.stdout | str contains owned) or ($owned and ($out.stdout | str contains changed)) { written-record $a.target }
                    {output: (if ($a.decl.then | is-not-empty) { run-exec ($a | update decl.argv $a.decl.then) $dir } else { "" })}
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
                        if $a.decl.kind == "file" { written-forget $a.target }
                        if ($a.decl.aside? | default null) != null and ($a.decl.aside | path exists) { ^mv -n $a.decl.aside $a.target }
                        {}
                    }
                }
                "forget" => { if $a.decl.kind == "file" { written-forget $a.target }; {} }
                "exec" => { {output: (run-exec $a $dir)} }
            }
            | {ok: true, error: null, aside: ($in.aside? | default null), output: ($in.output? | default "")}
        } catch {|e| {ok: false, error: $e.msg, aside: null, output: ""} }
        let ms = since-ms $start
        log-record (if $result.ok { "DEBUG" } else { "ERROR" }) $"($a.kind) ($a.target)" {module: $a.module, kind: $a.kind, target: $a.target, ms: $ms, outcome: (if $result.ok { "ok" } else { $result.error })}
        $a | merge $result | insert ms $ms
    }
    let unit_root = unit-dir
    if ($outcomes | any {|o| $o.ok and ($o.target | str starts-with $unit_root) }) {
        ^systemctl $"--($scope)" daemon-reload
    }
    $outcomes ++ $unreadable
}

# Records what the module now owns; a failed action keeps its previous output and clears the input hash
# so the next run plans it again.
export def state-write [id: string, verb: string, input: string, actions: list<record>, outcomes: list<record>, prev: list<record>]: nothing -> nothing {
    let done = $outcomes | where ok | reduce --fold {} {|o, acc| $acc | upsert $o.target $o }
    let failed = $outcomes | where not ok | get target
    let owned = $actions | where {|a| ($a.decl.kind == "exec" and $a.decl.creates? != null and $a.kind in [skip exec]) or $a.decl.kind in [file link unit] and $a.kind not-in [remove forget unmask] and not ($a.kind == "disable" and $a.decl.state? != "disabled") } | each {|a|
        let before = $prev | where target == $a.target | get --optional 0
        if $a.kind == "skip" or $a.target in $done {
            {
                kind: $a.decl.kind
                target: $a.target
                hash: (if $a.decl.kind == "file" { $a.after } else { null })
                generated: ($a.decl.generated? | default false)
                source: (if $a.decl.kind == "exec" { $a.decl.creates } else { $a.decl.source })
                state: $a.decl.state?
                aside: ($done | get --optional $a.target | get --optional aside | default ($before.aside? | default null))
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
