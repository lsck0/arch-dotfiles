# Per-machine drift reports: what this machine runs that no module declares, kept in git-crypt so a machine's
# package set stays out of the public repo; no timestamp, so an unchanged report makes no diff.

use pipeline.nu [pipeline-load]
use modules.nu [modules-packages]
use platform.nu [platform-groups-all]
use ledger.nu [ledger-get PACKAGES_DENY]
use secrets.nu [secrets-wanted]
use state.nu [SYSTEM_STATE]

const REPO = path self ../..
const REPORTS = path self ../../configs/secrets/state/drift
const SUBMODULE = path self ../../configs/secrets
const SHOWN_MAX = 12

def ledger [layer: string, kind: string]: nothing -> list<string> {
    with-env {DOT_LAYER: $layer} { ledger-get $kind }
}

def also-closure [scope: string, units: list<string>]: nothing -> list<string> {
    mut seen = []
    mut next = $units
    while ($next | is-not-empty) {
        let batch = $next
        let found = do { ^systemctl $"--($scope)" cat ...$batch } | complete | get stdout | lines
            | parse "Also={units}" | get units | each { split row " " } | flatten | where $it != "" | uniq
        let known = $seen ++ $batch
        $seen = $known
        $next = $found | where $it not-in $known
    }
    $seen | where $it not-in $units
}

def units-by-hand [scope: string, layer: string]: nothing -> list<string> {
    let owned = ledger $layer unit | parse "{scope} {name}" | where scope == $scope | get name
    let also = also-closure $scope $owned
    ^systemctl $"--($scope)" list-unit-files --state=enabled --no-legend | lines
    | parse --regex '^(?<name>\S+)\s+\S+\s+(?<preset>\S+)' | where preset != enabled and name not-in $also
    | get name | where $it not-in $owned | sort
}

def packages-missing [names: list<string>]: nothing -> list<string> {
    with-env {LC_ALL: C} { do { ^pacman -Qq ...$names } | complete }
    | get stderr | lines | parse "error: package '{name}' was not found" | get name
    | where {|n| (do { ^pacman -Qqg $n } | complete).exit_code != 0 }
}

# This machine's report as text: missing and hand-installed packages, units enabled by hand, the ledger.
export def drift-report []: nothing -> string {
    let ctx = pipeline-load $REPO system
    if $ctx.platform.file == null { error make {msg: $"drift: no platform file for (sys host | get hostname)"} }
    let machine = $SYSTEM_STATE | path join ledger
    if not ($machine | path exists) {
        error make {msg: $"drift: no machine ledger at ($machine), run dot apply --packages first"}
    }
    let declared = modules-packages $REPO $ctx.modules $ctx.platform | get pacman
    let pkgs = ledger system pkg
    [
        $"# drift report of ($ctx.platform.hostname), dot internal drift publish"
        $"groups ($ctx.platform.groups | str join ' ')"
        ...(ledger system snapshot | each { $"snapshot ($in)" })
        ...(packages-missing $declared | each { $"missing ($in)" })
        ...(^pacman -Qqe | lines | where $it not-in $pkgs and not ($it =~ $PACKAGES_DENY) | sort | each { $"hand ($in)" })
        ...(units-by-hand system system | each { $"unit-hand system ($in)" })
        ...(units-by-hand user user | each { $"unit-hand user ($in)" })
        ...($pkgs | each { $"pkg ($in)" })
        ...(ledger system unit | each { $"unit ($in)" })
        ...(ledger user unit | each { $"unit ($in)" })
    ] | str join "\n" | $"($in)\n"
}

# Writes the report to configs/secrets/state/drift/<host> when it changed; nothing without secrets pulled.
export def drift-publish []: nothing -> nothing {
    if not (secrets-wanted) or not ($SUBMODULE | path join .git | path exists) { return }
    let dest = $REPORTS | path join (sys host | get hostname)
    let report = drift-report
    if ($dest | path exists) and (open --raw $dest) == $report { return }
    mkdir $REPORTS
    $report | save --force $"($dest).new"
    ^chmod 600 $"($dest).new"
    mv --force $"($dest).new" $dest
    print $"drift: published ($dest), dot sync commits it"
}

def names [kind: string, report: path]: nothing -> list<string> {
    open --raw $report | lines | where ($it | str starts-with $"($kind) ")
    | each { str substring (($kind | str length) + 1).. }
    | uniq | sort
}

def line [label: string, names: list<string>]: nothing -> nothing {
    if ($names | is-empty) { return }
    let more = if ($names | length) > $SHOWN_MAX { $" \(+(($names | length) - $SHOWN_MAX) more\)" } else { "" }
    let count = $names | length | fill --alignment right --width 3
    print $"  ($label | fill --width 24) ($count)  ($names | first $SHOWN_MAX | str join ' ')($more)"
}

def snapshot-of [report: path]: nothing -> string {
    names snapshot $report | each { split row " " | first 2 | str join " " } | str join "\n"
}

export def drift-view []: nothing -> nothing {
    let reports = glob ($REPORTS | path join "*") --no-dir | where not ($it | str ends-with ".new") | sort
    if ($reports | is-empty) {
        error make {msg: "drift: nothing published in configs/secrets/state/drift yet: dot internal drift publish on each machine, dot sync"}
    }
    for report in $reports {
        let host = $report | path basename
        let age = ^git -C ($REPORTS | path dirname) log -1 --follow --diff-filter=AM --format=%cs -- $"drift/($host)" | str trim
            | if $in == "" { ls $report | get 0.modified | format date "%F" } else { $in }
        print $"($host) \(report of ($age)\)"
        let platform = glob ($REPO | path join platforms *.nuon) | where not ($it | str ends-with ".options.nuon")
            | where { (open $in | get --optional hostname) == $host } | get --optional 0
        if $platform != null {
            let published = names groups $report | each { split row " " } | flatten | uniq
            let declared = open $platform | get groups? | default []
                | if ($in | is-empty) { platform-groups-all $REPO } else { $in }
            line "groups to add (config)" ($declared | where $it not-in $published | sort)
            line "groups to drop (config)" ($published | where $it not-in $declared | sort)
        } else {
            print $"  no platform has hostname ($host), its groups are not declared in the repo"
        }
        line "declared, not installed" (names missing $report)
        line "installed by hand" (names hand $report)
        line "units enabled by hand" (names unit-hand $report | each { str replace " " ":" })
        print $"  ('snapshot' | fill --width 24)      (snapshot-of $report | default --empty none)"
    }
    if ($reports | length) < 2 { return }
    print "across hosts"
    let everywhere = $reports | skip 1
        | reduce --fold (names hand $reports.0) {|r, acc| $acc | where $it in (names hand $r) }
    line "by hand on every host" $everywhere
    for a in $reports {
        for b in ($reports | where $it != $a) {
            let label = $"($a | path basename) by hand, ($b | path basename) managed"
            line $label (names hand $a | where $it in (names pkg $b))
        }
    }
    let snapshots = $reports | each { snapshot-of $in } | where $it != "" | uniq | sort
    if ($snapshots | length) > 1 { print $"  ('snapshots differ' | fill --width 24)      ($snapshots | str join ';')" }
}
