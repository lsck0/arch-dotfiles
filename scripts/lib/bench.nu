# Benchmarks behind dot test bench: each one a command a person waits on, timed over warm runs against a budget set
# from what they feel. A run's results land as json in $XDG_STATE_HOME/dotfiles/bench, and the next run prints each
# bench's delta to its last run. Every dot a bench starts runs with DOT_SYSTEM=skip and its run log is removed again,
# so dot log and the runs dot status reads stay as they were.

use state.nu [xdg]
use log.nu [runs-dir]
use cli.nu [build]

const DOT = path self ../dot.nu
const TOGGLES_DIR = path self ../toggles
const TOGGLE_STATUS = path self ../toggles/status.nu
const SCHEMA = path self ../../configs/desktop/quickshell/config/plugins/settings/Schema.js
const METRICS = path self ../../configs/core/alloy/scripts/desktop-metrics.nu
const QML_RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
const RESULTS_PARTS = [dotfiles bench]
const RUNS_DEFAULT = 20
# commands of a second and more: fewer runs keep the suite to a few minutes
const RUNS_SLOW = 10
const RUNS_LINT = 3
const WARMUP_RUNS = 2
const PERCENTILE_TAIL = 0.95
const GROUP_DEFAULT = "default"
const GROUP_SLOW = "slow"
# a cheap module for the no-op apply of one: two config files, no hook
const MODULE_CHEAP = "core/btop"
# what a person types into the settings window: first keystrokes, words, and the newcomer's words the synonyms catch
const SEARCH_QUERIES = [
    b th wi bluetooth font theme dark wifi vpn keyboard "caps lock" "screen timeout" wallpaper "monitor scale"
    "night light" printer docker dpi idle browser proxy git
]
# dot status and dot status --json exit 1 when a check fails; plan and apply exit 3 with work pending
const EXITS_STATUS = [0 1]
const EXITS_APPLY = [0 3]
const EXITS_OK = [0]
# a median this much slower than the bench's last run is called out under the table
const DELTA_NOTABLE = 0.10
const COLUMNS = [
    [key width];
    [bench 26] [budget 7] [best 9] [median 9] [p95 9] [max 9] [spread 9] [runs 5] [verdict 8] [median_delta 13]
    [p95_delta 10]
]

def ms-from [duration: duration]: nothing -> float { ($duration | into int) / 1_000_000 }

def ms-text [ms: float]: nothing -> string { $ms | math round --precision 1 | into string }

# The run log a dot started under DOT_RUN_POINTER, with its side files: gone, so the benches never prune or shadow a
# real run's.
def run-forget [pointer: path]: nothing -> nothing {
    let run = open --raw $pointer | str trim
    if $run == "" { return }
    let id = $run | path parse | get stem
    glob ($run | path dirname | path join $"($id).*") | each { rm --force $in } | ignore
}

# argv once under the bench environment: its reply and its wall time.
def process-run [argv: list<string>, scratch: path]: nothing -> record {
    let pointer = mktemp --tmpdir-path $scratch
    let start = date now
    let reply = with-env {DOT_SYSTEM: skip, DOT_RUN_POINTER: $pointer} { run-external ...$argv | complete }
    let ms = ms-from ((date now) - $start)
    run-forget $pointer
    rm --force $pointer
    $reply | insert ms $ms
}

# One timed run of argv; an exit outside ok fails the bench with the command's own last lines.
def process-time-ms [argv: list<string>, ok: list<int>, scratch: path]: nothing -> float {
    let reply = process-run $argv $scratch
    if $reply.exit_code not-in $ok {
        let tail = $reply.stderr + $reply.stdout | lines | last 5 | str join "\n"
        error make {msg: $"`($argv | str join ' ')` exited ($reply.exit_code), want one of ($ok | str join ' ')\n($tail)"}
    }
    $reply.ms
}

def process-samples [argv: list<string>, ok: list<int>, runs: int, warmup: int, scratch: path]: nothing -> list<float> {
    for _ in 0..<$warmup { process-time-ms $argv $ok $scratch | ignore }
    0..<$runs | each { process-time-ms $argv $ok $scratch }
}

# What the settings window loads, captured once: the search bench times only the search, never the load.
def settings-data-js [scratch: path]: nothing -> string {
    let capture = {|argv: list<string>|
        let reply = process-run $argv $scratch
        if ($reply.stdout | str trim | is-empty) { error make {msg: $"`($argv | str join ' ')` printed nothing: ($reply.stderr | str trim)"} }
        $reply.stdout | from json | to json --raw
    }
    [
        ".pragma library"
        $"var options = (do $capture [$DOT set --json])"
        $"var toggles = (do $capture [$TOGGLE_STATUS --options])"
        $"var status = (do $capture [$DOT status --json])"
    ] | str join "\n"
}

# Schema.js sections() and rows() as Settings.qml runs them on each keystroke, over the live data: one sample per
# query per round, printed by the QML test and read back here. Date.now() is the clock QML has: whole milliseconds.
def search-samples [runs: int, warmup: int, scratch: path]: nothing -> list<float> {
    settings-data-js $scratch | save --force ($scratch | path join data.js)
    $"import QtQuick
import QtTest
import \"file://($SCHEMA)\" as Schema
import \"file://($scratch)/data.js\" as Data

TestCase {
  name: \"bench\"
  readonly property var queries: ($SEARCH_QUERIES | to json --raw)

  function keystroke\(modules, machine, query\) {
    var found = Schema.search\(modules, Data.toggles, query, Data.status, machine\)
    var sections = Schema.sections\(modules, Data.toggles, query, Data.status, machine, found\)
    var section = sections[0] || null
    return Schema.rows\(modules, Data.toggles, section ? section.id : \"\", query, Data.status, machine, found\).length
  }

  function test_search\() {
    var modules = Data.options.modules.map\(Schema.moduleNormalize\)
    var machine = Data.options.platform ? Schema.moduleNormalize\(Data.options.platform\) : null
    for \(var w = 0; w < ($warmup); w++\) for \(var q = 0; q < queries.length; q++\) keystroke\(modules, machine, queries[q]\)
    for \(var r = 0; r < ($runs); r++\) {
      for \(var i = 0; i < queries.length; i++\) {
        var start = Date.now\(\)
        var count = keystroke\(modules, machine, queries[i]\)
        console.log\(\"SAMPLE \" + \(Date.now\(\) - start\) + \" \" + count + \" \" + queries[i]\)
      }
    }
  }
}
" | save --force ($scratch | path join tst_bench.qml)
    let run = with-env {QT_QPA_PLATFORM: offscreen} { ^$QML_RUNNER -input ($scratch | path join tst_bench.qml) | complete }
    if $run.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($run.stdout)($run.stderr)"} }
    $run.stdout + $run.stderr | lines | parse --regex 'qml: SAMPLE (?<ms>\d+) ' | get ms | into float
}

def process-bench [name: string, budget_ms: int, argv: list<string>, ok: list<int>, runs: int, group: string]: nothing -> record {
    {
        name: $name, group: $group, budget_ms: $budget_ms, runs: $runs
        measure: {|runs, warmup, scratch| process-samples $argv $ok $runs $warmup $scratch }
    }
}

# The suite. Every budget is what a person waiting on it feels, never what the code does today.
def benches []: nothing -> list<record> {
    # a toggle's state on the bar, in the menu and in settings: past 200 ms a click shows the old state
    let toggles = glob ($TOGGLES_DIR | path join toggle-*.nu) | sort | each {|script|
        process-bench ($script | path parse | get stem) 200 [$script get --json] $EXITS_OK $RUNS_DEFAULT $GROUP_DEFAULT
    }
    [
        # the whole user layer with nothing to do, as dot sync runs it every time: a plan plus the writes, 5 s. First:
        # after an edit under scripts/lib every module's input changed, and only an apply records the new ones, so its
        # warmup leaves plan below timing the steady state instead of a re-evaluation of every module
        (process-bench apply-user 5000 [$DOT apply --user] $EXITS_APPLY $RUNS_SLOW $GROUP_DEFAULT)
        # one module after an edit, the inner loop of changing a config: past 2 s the loop drags
        (process-bench apply-one 2000 [$DOT apply $MODULE_CHEAP] $EXITS_APPLY $RUNS_SLOW $GROUP_DEFAULT)
        # a terminal command run before every apply to see what it would do: a few seconds before it reads as stuck
        (process-bench plan 3000 [$DOT plan] $EXITS_APPLY $RUNS_SLOW $GROUP_DEFAULT)
        # read in a terminal: two seconds before it feels slow for a report
        (process-bench status 2000 [$DOT status] $EXITS_STATUS $RUNS_SLOW $GROUP_DEFAULT)
        # the bar's and failure-notify's health check, on a timer: under a second so it never piles up
        (process-bench status-brief 1000 [$DOT status --brief] $EXITS_STATUS $RUNS_DEFAULT $GROUP_DEFAULT)
        # the settings window's System section and desktop-metrics read it: a second, then the section looks empty
        (process-bench status-json 1000 [$DOT status --json] $EXITS_STATUS $RUNS_DEFAULT $GROUP_DEFAULT)
        # what the settings window loads on open: past 750 ms the window sits empty long enough to notice
        (process-bench set-json 750 [$DOT set --json] $EXITS_OK $RUNS_DEFAULT $GROUP_DEFAULT)
        # the settings window's quick toggles, loaded beside dot set --json on open: the same 750 ms
        (process-bench toggles-status-options 750 [$TOGGLE_STATUS --options] $EXITS_OK $RUNS_DEFAULT $GROUP_DEFAULT)
        # every toggle at once, as the menu opens: 300 ms, a toggle's 200 plus room for the fan-out
        (process-bench toggles-status 300 [$TOGGLE_STATUS] $EXITS_OK $RUNS_DEFAULT $GROUP_DEFAULT)
        # the timer's user half every 5 minutes at Nice=10: three seconds keeps it a blip, its dot status --json included
        (process-bench desktop-metrics-user 3000 [$METRICS user] $EXITS_OK $RUNS_SLOW $GROUP_DEFAULT)
        # one keystroke in the settings search: past 100 ms typing lags behind the list
        {
            name: settings-search, group: $GROUP_DEFAULT, budget_ms: 100, runs: $RUNS_DEFAULT
            measure: {|runs, warmup, scratch| search-samples $runs $warmup $scratch }
        }
        # the gate before every report (AGENTS.md: about a minute); 90 s before an agent's loop stalls
        (process-bench lint 90000 [$DOT test lint] $EXITS_OK $RUNS_LINT $GROUP_SLOW)
    ] ++ $toggles
}

# Nearest rank: the smallest sample at or above the fraction of all.
export def percentile [fraction: float]: list<float> -> float {
    let sorted = $in | sort
    let rank = [($fraction * ($sorted | length) | math ceil) 1] | math max
    $sorted | get ($rank - 1)
}

export def samples-summary [budget_ms: int]: list<float> -> record {
    let samples = $in
    let p95 = $samples | percentile $PERCENTILE_TAIL
    {
        runs: ($samples | length)
        budget_ms: $budget_ms
        best_ms: ($samples | math min)
        median_ms: ($samples | math median)
        p95_ms: $p95
        max_ms: ($samples | math max)
        stdev_ms: ($samples | math stddev)
        within: ($p95 <= $budget_ms)
    }
}

# Each bench's median and p95 against its newest earlier run, as fractions; null where it never ran before.
export def results-delta [earlier: list<record>]: list<record> -> list<record> {
    $in | each {|now|
        let before = $earlier | where name == $now.name | get --optional 0
        if $before == null or $before.median_ms == 0 or $before.p95_ms == 0 {
            {name: $now.name, median: null, p95: null}
        } else {
            {name: $now.name, median: ($now.median_ms / $before.median_ms - 1), p95: ($now.p95_ms / $before.p95_ms - 1)}
        }
    }
}

def percent [fraction: any]: nothing -> string {
    if $fraction == null { return "" }
    let shown = $fraction * 100 | math round --precision 1
    $"(if $shown >= 0 { '+' } else { '' })($shown)%"
}

def results-dir []: nothing -> path { xdg state ...$RESULTS_PARTS }

# Every earlier run's results, newest first.
def results-earlier []: nothing -> list<record> {
    glob (results-dir | path join "*.json") | sort --reverse | each {|f| try { open $f | get results } catch { [] } } | flatten
}

# Fixed-width columns: nushell's table cuts columns at the terminal's width, or at 80 with none.
def results-print [results: list<record>, deltas: list<record>]: nothing -> nothing {
    let line = {|row| $COLUMNS | each {|c| $row | get $c.key | into string | fill --width $c.width } | str join "" | str trim --right }
    print (do $line ($COLUMNS | reduce --fold {} {|c, acc| $acc | insert $c.key ($c.key | str replace "_" " ") }))
    $results | each {|r|
        let delta = $deltas | where name == $r.name | get 0
        print (do $line {
            bench: $r.name
            budget: $r.budget_ms
            best: (ms-text $r.best_ms)
            median: (ms-text $r.median_ms)
            p95: (ms-text $r.p95_ms)
            max: (ms-text $r.max_ms)
            spread: $"+-(ms-text $r.stdev_ms)"
            runs: $r.runs
            verdict: (if $r.within { "ok" } else { "MISS" })
            median_delta: (percent $delta.median)
            p95_delta: (percent $delta.p95)
        })
    } | ignore
    print "times in ms; spread: standard deviation; delta: against the newest earlier run of the bench"
}

# The runs dir as it was, so a log a bench's dot pruned comes back; the logs the benches wrote are gone already.
def runs-restore [snapshot: path]: nothing -> nothing {
    glob ($snapshot | path join "*") | each {|f|
        let dest = runs-dir | path join ($f | path basename)
        if not ($dest | path exists) { cp $f $dest }
    } | ignore
}

# Runs the group's benches (or those whose name starts with only, in any group), prints the table with each bench's
# delta to its last run and saves the results; true when every p95 is within its budget.
export def bench-run [only: any, runs: any, slow: bool]: nothing -> bool {
    let group = if $slow { $GROUP_SLOW } else { $GROUP_DEFAULT }
    let chosen = benches | where {|b| if $only != null { $b.name | str starts-with $only } else { $b.group == $group } }
    if ($chosen | is-empty) { error make {msg: $"no bench named ($only)*; one of: (benches | get name | str join ' ')"} }
    let scratch = mktemp --directory --tmpdir dot-bench.XXXXXX
    let snapshot = $scratch | path join runs
    mkdir $snapshot
    glob (runs-dir | path join "*") | each { cp $in $snapshot } | ignore
    let outcome = try {
        let results = $chosen | each {|b|
            let count = $runs | default $b.runs
            print --stderr $"dot bench: ($b.name), ($count) runs"
            let samples = do $b.measure $count $WARMUP_RUNS $scratch
            {name: $b.name} | merge ($samples | samples-summary $b.budget_ms)
        }
        {ok: true, results: $results}
    } catch {|e| {ok: false, error: $e} }
    runs-restore $snapshot
    rm --recursive --force $scratch
    if not $outcome.ok { error make $outcome.error }
    let deltas = $outcome.results | results-delta (results-earlier)
    results-print $outcome.results $deltas
    $deltas | where {|d| $d.median != null and $d.median > $DELTA_NOTABLE } | each {|d|
        print $"dot bench: ($d.name) median (percent $d.median) against its last run"
    } | ignore
    let now = date now
    mkdir (results-dir)
    let file = results-dir | path join $"($now | format date '%Y%m%dT%H%M%S').json"
    {
        time: ($now | format date '%+')
        build: (build)
        load: (open /proc/loadavg | split row " " | first 3 | into float)
        cpus: (^nproc | into int)
        results: $outcome.results
    } | to json | save --force $file
    print $"dot bench: saved ($file)"
    let missed = $outcome.results | where not within
    $missed | each { print $"dot bench: ($in.name) p95 (ms-text $in.p95_ms) ms over its ($in.budget_ms) ms budget" } | ignore
    $missed | is-empty
}
