use log.nu *
use state.nu [state-dir state-locked path-kind nu-bin LIB_DIR]
use written.nu [sync-guard preserve-aside written-file written-record written-forget]
use json.nu [json-edits-apply]
use module.nu [DECL_KEYS DECL_KINDS unit-dir]
use ini.nu [ini-apply]

# a link into one of these is the dotfiles' own, replaced without asking
const OWN_LINK_PREFIXES = ["/var/lib/dotfiles/"]

export def state-path [id: string, verb: string]: nothing -> path {
    state-dir | path join modules $id $"($verb).nuon"
}

export def state-read [id: string, verb: string]: nothing -> record {
    let file = state-path $id $verb
    if ($file | path exists) { open $file } else { {input: "", run: "", time: "", outputs: []} }
}

export def assert-shape [value: record, keys: list<string>, what: string]: nothing -> nothing {
    if ($value | columns | sort) != ($keys | sort) {
        error make {msg: $"($what) has keys ($value | columns | str join ' '), wants ($keys | str join ' '): ($value | to nuon)"}
    }
}

def sha [text: any]: nothing -> string {
    $text | hash sha256
}

# a unit systemd does not know answers on stderr only, so the batch falls back to asking each
export def unit-states [scope: string, units: list<string>]: nothing -> list<string> {
    let batch = ^systemctl $"--($scope)" is-enabled ...$units | complete | get stdout | lines
    if ($batch | length) == ($units | length) { return $batch }
    $units | each {|u| ^systemctl $"--($scope)" is-enabled $u | complete | get stdout | str trim | if ($in | is-empty) { "not-found" } else { $in } }
}

export def observe [targets: list<string>, units: list<string>, scope: string]: nothing -> record {
    let paths = $targets | uniq | each {|t|
        let type = path-kind $t
        {
            target: $t
            type: $type
            # a root-only file seen by a user's plan of the system layer
            hash: (if $type == file { try { open --raw $t | sha $in } catch { "unreadable" } } else { null })
            link: (if $type == symlink { ^readlink $t } else { null })
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

# a file changed since its last apply is drift, kept unless forced; one the dotfiles never wrote is taken over. both
# are preserved aside first
export def plan-module [id: string, decls: list<record>, prev: list<record>, seen: record, recorded: record, repo: string, force: bool]: nothing -> list<record> {
    for decl in $decls {
        assert-shape $decl $DECL_KEYS $"declaration of ($id)"
        if $decl.kind not-in $DECL_KINDS { error make {msg: $"($id) declares a ($decl.kind), not one of ($DECL_KINDS | str join ' ')"} }
    }
    let wanted = $decls | each {|d|
        let obs = $seen.paths | get --optional $d.target
        if $obs.hash? == "unreadable" { return (action $id unreadable $d.target "unreadable as this user, checked at apply" $d null null) }
        match $d.kind {
            "file" => {
                let want = if $d.content != null { sha $d.content } else { open --raw $d.source | sha $in }
                let rec = $prev | where target == $d.target | get --optional 0.hash | default ($recorded | get --optional $d.target)
                if $obs.type == "" {
                    action $id create $d.target "missing" $d null $want
                } else if $obs.type == symlink and ((own-link $obs.link $repo) or not ($d.target | path exists)) {
                    action $id update $d.target "a link of the old linked form" $d $obs.link $want
                } else if $obs.type == file and $obs.hash == $want {
                    if $rec == $want { action $id skip $d.target "" $d $want $want } else { action $id record $d.target "already this content" $d $obs.hash $want }
                } else if $obs.type == file and ($d.generated or $rec == $obs.hash) {
                    action $id update $d.target "changed in the module" $d $obs.hash $want
                } else if $rec == null {
                    action $id update $d.target "not the dotfiles' own yet: preserved aside" ($d | insert preserve true) $obs.hash $want
                } else if $force {
                    action $id update $d.target "drift, forced: preserved aside" ($d | insert preserve true) $obs.hash $want
                } else {
                    action $id drift $d.target "changed since the last apply" $d $obs.hash $want
                }
            }
            "link" => {
                if $obs.type == symlink and $obs.link == $d.source {
                    action $id skip $d.target "" $d $obs.link $d.source
                } else if $obs.type == "" or ($obs.type == symlink and ((own-link $obs.link $repo) or not ($d.target | path exists))) {
                    action $id create $d.target "missing" $d $obs.link $d.source
                } else if $obs.type == file and $obs.hash == (open --raw $d.source | sha $in) {
                    action $id update $d.target "a copy of the source" $d $obs.hash $d.source
                } else if $force {
                    action $id update $d.target "drift, forced: preserved aside" ($d | insert preserve true) $obs.hash $d.source
                } else {
                    action $id drift $d.target "not the dotfiles' own" $d $obs.hash $d.source
                }
            }
            "json" => {
                let raw = if $obs.type == file { open --raw $d.target } else { "" }
                let current = if ($raw | str trim | is-empty) { {} } else { $raw | from json }
                let merged = $current | json-edits-apply $d.edits
                if $merged == $current and ($raw | is-not-empty) { action $id skip $d.target "" $d null null } else { action $id merge $d.target "keys differ" $d $obs.hash null }
            }
            "ini" => {
                let raw = if $obs.type == file { open --raw $d.target } else { "" }
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
        match $o.kind {
            "file" => {
                if $obs.type == "" { action $id forget $o.target "already gone" $o null null
                } else if $obs.hash == $o.hash { action $id remove $o.target "no longer declared" $o $o.hash null
                } else { action $id drift $o.target "no longer declared, changed since: left in place" $o $obs.hash null }
            }
            "link" => {
                if $obs.type == symlink and $obs.link == $o.source { action $id remove $o.target "no longer declared" $o $o.source null } else { action $id forget $o.target "not the link it was" $o null null }
            }
            "unit" => (match ($o.state? | default enabled) {
                "enabled" => (action $id disable $o.target "no longer declared" ($o | insert now true) enabled null)
                "masked" => (action $id unmask $o.target "no longer declared" $o masked null)
                _ => (action $id forget $o.target "no longer declared" $o null null)
            })
            _ => null
        }
    } | compact
    $wanted ++ ($orphans | sort-by {|a| if $a.kind in [disable unmask] { 0 } else { 1 } })
}

# stops at a non-empty dir, a link or home; never fails the removal
def prune-parents [start: path]: nothing -> nothing {
    mut dir = $start
    while $dir != $nu.home-dir and $dir != "/" and (path-kind $dir) == "dir" and (try { ls --all $dir | is-empty } catch { false }) {
        try { rm $dir } catch { break }
        $dir = $dir | path dirname
    }
}

def write-file [a: record]: nothing -> nothing {
    let d = $a.decl
    mkdir ($d.target | path dirname)
    let tmp = $"($d.target).dot-new"
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

def run-exec [a: record, dir: path]: nothing -> string {
    let out = do { cd $dir; command-stream $"($a.module) ($a.target)" $a.decl.argv }
    if $out.exit_code != 0 {
        error make {msg: $"($a.target) exited ($out.exit_code): ($out.tail)"}
    }
    $out.output
}

export def apply-module [actions: list<record>, dir: path, scope: string]: nothing -> list<record> {
    let outcomes = $actions | where kind not-in [skip drift unreadable] | each {|a|
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
                    # a unit's own --then (start it) needs the manager to know the new file first
                    if ($a.decl.then | is-not-empty) and ($a.target | str starts-with (unit-dir)) { ^systemctl $"--($scope)" daemon-reload }
                    let output = if ($a.decl.then | is-not-empty) { run-exec ($a | update decl.argv $a.decl.then) $dir } else { "" }
                    {aside: $aside, output: $output}
                }
                "record" => { written-record $a.target; {} }
                "merge" => {
                    sync-guard $a.target
                    mkdir ($a.target | path dirname)
                    if $a.decl.kind == "ini" {
                        # the same inode, so an app holding the file open keeps working
                        $a.decl.content | save --force $a.target
                    } else {
                        let recorded = recorded-hashes | get --optional $a.target | default ""
                        let out = state-locked $"(state-dir)/json.lock" json-update {file: $a.target, edits: $a.decl.edits, recorded_sum: $recorded} | complete
                        if ($out.stdout | str contains owned) { written-record $a.target }
                    }
                    {output: (if ($a.decl.then | is-not-empty) { run-exec ($a | update decl.argv $a.decl.then) $dir } else { "" })}
                }
                "enable" | "disable" => {
                    let now = if ($a.decl.now? | default false) { [--now] } else { [] }
                    ^systemctl $"--($scope)" $a.kind ...$now $a.target
                    {}
                }
                "mask" | "unmask" => { ^systemctl $"--($scope)" $a.kind $a.target; {} }
                "step" => { {output: (run-step $a $dir)} }
                "remove" => {
                    rm --force $a.target
                    prune-parents ($a.target | path dirname)
                    if $a.decl.kind == "file" { written-forget $a.target }
                    if ($a.decl.aside? | default null) != null and ($a.decl.aside | path exists) { ^mv -n $a.decl.aside $a.target }
                    {}
                }
                "forget" => { if $a.decl.kind == "file" { written-forget $a.target }; {} }
                "exec" => { {output: (run-exec $a $dir)} }
            }
            | {ok: true, error: null, aside: ($in.aside? | default null), output: ($in.output? | default "")}
        } catch {|e| {ok: false, error: $e.msg, aside: null, output: ""} }
        let ms = (date now) - $start | into int | $in // 1_000_000
        log-record (if $result.ok { "DEBUG" } else { "ERROR" }) $"($a.kind) ($a.target)" {module: $a.module, kind: $a.kind, target: $a.target, ms: $ms, outcome: (if $result.ok { "ok" } else { $result.error })}
        $a | merge $result | insert ms $ms
    }
    let unit_root = unit-dir
    if ($outcomes | any {|o| $o.ok and ($o.target | str starts-with $unit_root) }) {
        ^systemctl $"--($scope)" daemon-reload
    }
    $outcomes
}

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
    } | save --force $file
}
