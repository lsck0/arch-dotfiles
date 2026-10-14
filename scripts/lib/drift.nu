# drift across the machines this repo drives: each publishes its ledger and what it diverged by into
# secrets/drift/<host> (git-crypt: a machine's package set stays out of the public repo, sync carries it to the
# others), and the view diffs every published report against its platforms/<host>.nuon and against each other. a report
# holds no time, so an unchanged machine leaves the file and the worktree alone

use pipeline.nu [pipeline-load]
use modules.nu [modules-packages]
use platform.nu [platform-groups-all]
use ledger.nu [ledger-get]
use secrets.nu [secret-is-plaintext]
use state.nu [SYSTEM_STATE]

const REPO = path self ../..
const REPORTS = path self ../../secrets/drift
const WITNESS = path self ../../secrets/pgp_privatekey.asc
# names shown per line before the rest is only counted
const SHOWN_MAX = 12

def ledger [layer: string, kind: string]: nothing -> list<string> {
    with-env {DOT_LAYER: $layer} { ledger-get $kind }
}

# enabled against the vendor preset, neither owned nor pulled in by an owned unit's Also=; the rule the ledger's
# unit report follows during a run
def units-by-hand [scope: string, layer: string]: nothing -> list<string> {
    let owned = ledger $layer unit | parse "{scope} {name}" | where scope == $scope | get name
    let also = if ($owned | is-empty) { [] } else {
        do { ^systemctl $"--($scope)" cat ...$owned } | complete | get stdout | lines
        | parse "Also={units}" | get units | each { split row " " } | flatten
    }
    ^systemctl $"--($scope)" list-unit-files --state=enabled --no-legend | lines
    | parse --regex '^(?<name>\S+)\s+\S+\s+(?<preset>\S+)' | where preset != enabled and name not-in $also
    | get name | where $it not-in $owned | sort
}

# declared names neither installed nor provided nor a group with an installed member
def packages-missing [names: list<string>]: nothing -> list<string> {
    with-env {LC_ALL: C} { do { ^pacman -Qq ...$names } | complete }
    | get stderr | lines | parse "error: package '{name}' was not found" | get name
    | where {|n| (do { ^pacman -Qqg $n } | complete).exit_code != 0 }
}

# this machine's report
export def drift-report []: nothing -> string {
    let ctx = pipeline-load $REPO system
    if $ctx.platform.file == null { error make {msg: $"drift: no platform file for (sys host | get hostname)"} }
    let machine = $SYSTEM_STATE | path join ledger
    if not ($machine | path exists) {
        error make {msg: $"drift: no machine ledger at ($machine), run dot install first"}
    }
    let declared = modules-packages $REPO $ctx.modules $ctx.platform | get pacman
    let pkgs = ledger system pkg
    [
        $"# drift report of ($ctx.platform.hostname), dot drift publish"
        $"groups ($ctx.platform.groups | str join ' ')"
        ...(ledger system snapshot | each { $"snapshot ($in)" })
        ...(packages-missing $declared | each { $"missing ($in)" })
        ...(^pacman -Qqe | lines | where $it not-in $pkgs | sort | each { $"hand ($in)" })
        ...(units-by-hand system system | each { $"unit-hand system ($in)" })
        ...(units-by-hand user user | each { $"unit-hand user ($in)" })
        ...($pkgs | each { $"pkg ($in)" })
        ...(ledger system unit | each { $"unit ($in)" })
        ...(ledger user unit | each { $"unit ($in)" })
    ] | str join "\n" | $"($in)\n"
}

# the report into secrets/drift/<host>, only when it changed
export def drift-publish []: nothing -> nothing {
    if not (secret-is-plaintext $WITNESS) { error make {msg: "secrets is locked, unlock it first"} }
    let dest = $REPORTS | path join (sys host | get hostname)
    let report = drift-report
    if ($dest | path exists) and (open --raw $dest) == $report { return }
    mkdir $REPORTS
    $report | save --force $"($dest).new"
    mv --force $"($dest).new" $dest
    print $"drift: published ($dest), dot sync commits it"
}

def names [kind: string, report: path]: nothing -> list<string> {
    open --raw $report | lines | where ($it | str starts-with $"($kind) ")
    | each { str substring (($kind | str length) + 1).. }
    | uniq | sort
}

# the label, the count and the first SHOWN_MAX names, nothing for none
def line [label: string, names: list<string>]: nothing -> nothing {
    if ($names | is-empty) { return }
    let more = if ($names | length) > $SHOWN_MAX { $" \(+(($names | length) - $SHOWN_MAX) more\)" } else { "" }
    let count = $names | length | fill --alignment right --width 3
    print $"  ($label | fill --width 24) ($count)  ($names | first $SHOWN_MAX | str join ' ')($more)"
}

def snapshot-of [report: path]: nothing -> string {
    names snapshot $report | each { split row " " | first 2 | str join " " } | str join "\n"
}

# every published report: declared groups, missing and hand-installed packages, units enabled by hand, the
# snapshot, then what the hosts disagree on
export def drift-view []: nothing -> nothing {
    if not (secret-is-plaintext $WITNESS) { error make {msg: "drift: secrets/ is locked: dot secrets unlock"} }
    let reports = glob ($REPORTS | path join "*") --no-dir | where not ($it | str ends-with ".new") | sort
    if ($reports | is-empty) {
        error make {msg: "drift: nothing published in secrets/drift yet: dot drift publish on each machine, dot sync"}
    }
    for report in $reports {
        let host = $report | path basename
        let age = ^git -C ($REPORTS | path dirname) log -1 --format=%cs -- $"drift/($host)" | str trim
            | if $in == "" { ls $report | get 0.modified | format date "%F" } else { $in }
        print $"($host) \(report of ($age)\)"
        let platform = $REPO | path join platforms $"($host).nuon"
        if ($platform | path exists) {
            let published = names groups $report | each { split row " " } | flatten | uniq
            let declared = open $platform | get groups? | default []
                | if ($in | is-empty) { platform-groups-all $REPO } else { $in }
            line "groups to add (config)" ($declared | where $it not-in $published | sort)
            line "groups to drop (config)" ($published | where $it not-in $declared | sort)
        } else {
            print $"  no platforms/($host).nuon, its groups are not declared in the repo"
        }
        line "declared, not installed" (names missing $report)
        line "installed by hand" (names hand $report)
        line "units enabled by hand" (names unit-hand $report | each { str replace " " ":" })
        print $"  ('snapshot' | fill --width 24)      (snapshot-of $report | default --empty none)"
    }
    if ($reports | length) < 2 { return }
    print "across hosts"
    # by hand everywhere: a candidate for a module's packages
    let everywhere = $reports | skip 1
        | reduce --fold (names hand $reports.0) {|r, acc| $acc | where $it in (names hand $r) }
    line "by hand on every host" $everywhere
    for a in $reports {
        for b in ($reports | where $it != $a) {
            # what one machine manages and another has only by hand: declared in a group the other lacks
            let label = $"($a | path basename) by hand, ($b | path basename) managed"
            line $label (names hand $a | where $it in (names pkg $b))
        }
    }
    let snapshots = $reports | each { snapshot-of $in } | where $it != "" | uniq | sort
    if ($snapshots | length) > 1 { print $"  ('snapshots differ' | fill --width 24)      ($snapshots | str join ';')" }
}
