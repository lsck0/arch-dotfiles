#!/usr/bin/env -S nu --no-config-file
# Table cases for the package gate and the hold on dependents: pure records in, reasons and pending lines out, then
# pipeline-apply's scheduler over rows that run nothing; what is absent and which link sources are alive against fake
# tools first on PATH.
use pipeline.nu [packages-gate packages-absent links-alive module-held pending-lines pipeline-apply]
use modules.nu [modules-eval]
use module.nu [step]
use cause.nu [cause-hint]
use online.nu [OFFLINE_PENDING remote-pending]

const MISSING_HINT = "dot apply --packages"

def fail [msg: string] { error make {msg: $"pipeline.test: ($msg)"} }

def gate-cases []: nothing -> nothing {
    let declared = [
        [id pacman flatpak nix];
        [a/none [] [] []]
        [a/installed [bash] [] []]
        [a/pacman [bash sbctl] [] []]
        [a/flatpak [] [org.example.App] []]
        [a/nix [bash] [] [devenv]]
    ]
    let absent = {pacman: [sbctl], flatpak: [org.example.App], nix: [devenv]}
    let gate = packages-gate $declared $absent
    let cases = [
        [id wants];
        [a/none null]
        [a/installed null]
        [a/pacman $"packages missing: sbctl; ($MISSING_HINT)"]
        [a/flatpak $"packages missing: org.example.App; ($MISSING_HINT)"]
        [a/nix $"packages missing: devenv; ($MISSING_HINT)"]
    ]
    for c in $cases {
        let got = $gate | get --optional $c.id
        if $got != $c.wants { fail $"gate ($c.id): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
    if (packages-gate $declared {pacman: [], flatpak: [], nix: []}) != {} { fail "gate: nothing absent still holds a module" }
}

def held-cases []: nothing -> nothing {
    let done = {b/ok: ok, b/failed: failed, b/pending: pending}
    let cases = [
        [name m wants];
        ["no deps" {id: x, deps: [], pending: null} null]
        ["dep ok" {id: x, deps: [b/ok], pending: null} null]
        ["dep outside the run" {id: x, deps: [b/elsewhere], pending: null} null]
        ["dep failed" {id: x, deps: [b/ok b/failed], pending: null} "waits on b/failed (failed)"]
        ["dep pending" {id: x, deps: [b/pending], pending: null} "waits on b/pending (pending)"]
        ["own packages first" {id: x, deps: [b/failed], pending: "packages missing: y"} "packages missing: y"]
        ["row without the fields" {id: x} null]
    ]
    for c in $cases {
        let got = module-held $c.m $done
        if $got != $c.wants { fail $"held ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}

def pending-lines-cases []: nothing -> nothing {
    let earlier = ["a/old: packages missing: x" "a/other: packages missing: y"]
    let results = [{id: a/old, ok: true, pending: null} {id: a/new, ok: true, pending: "waits on a/old (failed)"}]
    # dependents an earlier run held behind a failure, not planned by this partial one
    let holds = [
        "c/one: waits on b/fixed (failed)"
        "c/two: waits on b/fixed (failed), b/broken (failed)"
        "c/three: waits on b/elsewhere (pending)"
        "c/four: waits on b/held (pending)"
        "c/five: packages missing: z; dot apply --packages"
    ]
    let partial = [{id: b/fixed, ok: true, pending: null} {id: b/broken, ok: false, pending: null} {id: b/held, ok: true, pending: "packages missing: q"}]
    let cases = [
        [name earlier results full planned wants];
        ["full run replaces" $earlier $results true [a/old a/new] ["a/new: waits on a/old (failed)"]]
        ["partial keeps the rest" $earlier $results false [a/old a/new] ["a/other: packages missing: y" "a/new: waits on a/old (failed)"]]
        [
            "partial drops holds on modules now ok" $holds $partial false [b/fixed b/broken b/held]
            ["c/two: waits on b/fixed (failed), b/broken (failed)" "c/three: waits on b/elsewhere (pending)" "c/four: waits on b/held (pending)" "c/five: packages missing: z; dot apply --packages" "b/held: packages missing: q"]
        ]
    ]
    for c in $cases {
        let got = pending-lines $c.earlier $c.planned $c.results $c.full
        if $got != $c.wants { fail $"pending lines ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}

# A fresh dir of executables, each a sh script, for the front of PATH.
def tools-fake [dir: path, scripts: record]: nothing -> path {
    mkdir $dir
    $scripts | items {|name, body|
        let file = $dir | path join $name
        $"#!/bin/sh\n($body)\n" | save --force $file
        ^chmod +x $file
    } | ignore
    $dir
}

# pacman -T answers the names not installed, -Qqg whether a group has a member installed
const PACMAN_FAKE = 'case "$1" in
-T) shift; for n; do case "$n" in bash|base-devel) ;; *) echo "$n" ;; esac; done ;;
-Qqg) [ "$2" = xorg ] ;;
*) exit 2 ;;
esac'

def absent-cases [work: path]: nothing -> nothing {
    let declared = [
        [id pacman flatpak nix];
        [p/a [bash sbctl xorg gnome] [org.example.Here org.example.Gone] [devenv]]
        [p/b [base-devel] [] [ripgrep]]
    ]
    let listing = {
        pacman: $PACMAN_FAKE
        flatpak: 'printf "org.example.Here\n"'
        nix: 'printf "{\"elements\": {\"devenv\": {}}}\n"'
    }
    let failing = {pacman: $PACMAN_FAKE, flatpak: 'echo "flatpak: no session bus" >&2; exit 1', nix: 'echo "cannot connect to socket at /nix/var/nix/daemon-socket/socket" >&2; exit 1'}
    let cases = [
        [name tools wants];
        ["a group counts when any member is installed" $listing {pacman: [sbctl gnome], flatpak: [org.example.Gone], nix: [ripgrep]}]
        ["a failing listing misses every name of its kind" $failing {pacman: [sbctl gnome], flatpak: [org.example.Here org.example.Gone], nix: [devenv ripgrep]}]
        ["a missing tool misses every name of its kind" {pacman: $PACMAN_FAKE} {pacman: [sbctl gnome], flatpak: [org.example.Here org.example.Gone], nix: [devenv ripgrep]}]
    ]
    for c in ($cases | enumerate) {
        # PATH holds the fakes alone, so a real flatpak or nix never answers
        let fakes = tools-fake ($work | path join $"absent-($c.index)") $c.item.tools
        let got = with-env {PATH: [$fakes]} { packages-absent $declared }
        if $got != $c.item.wants { fail $"absent \(($c.item.name)\): got ($got | to nuon), wants ($c.item.wants | to nuon)" }
    }
    if (packages-absent ($declared | update pacman [] | update flatpak [] | update nix [])) != {pacman: [], flatpak: [], nix: []} { fail "absent: nothing declared misses a name" }
}

def alive-cases [work: path]: nothing -> nothing {
    let there = $work | path join there
    touch $there
    let gone = $work | path join gone
    let wants = {$there: true, $gone: false}
    # a batch that answers too few, one that hangs past the probe's bound: each source is probed on its own
    let shells = [
        [name body];
        ["short batch" 'echo y']
        ["batch timed out" 'sleep 30']
    ]
    for s in ($shells | enumerate) {
        let fakes = tools-fake ($work | path join $"alive-($s.index)") {sh: $s.item.body}
        let got = with-env {PATH: [$fakes ...$env.PATH]} { links-alive [$there $gone] }
        if $got != $wants { fail $"links alive \(($s.item.name)\): got ($got | to nuon), wants ($wants | to nuon)" }
    }
    let got = links-alive [$there $gone]
    if $got != $wants { fail $"links alive (one batch): got ($got | to nuon), wants ($wants | to nuon)" }
    if (links-alive []) != {} { fail "links alive: no sources answers something" }
}

# rows that are no native module (ok, nothing run) or carry a plan error (failed): the scheduler alone decides
def row [id: string, after: list<string>, --deps: list<string> = [], --pending: string, --error: string]: nothing -> record {
    {
        id: $id, dir: "/nonexistent", after: $after, deps: $deps, level: 0, serial: false, cfg: {}, options: {}, force: false
        native: ($error != null), skipped: false, input: "", prev: [], actions: [], error: $error, pending: $pending
    }
}

def apply-cases []: nothing -> nothing {
    let planned = [
        (row g/fine [])
        (row g/nopkg [] --pending "packages missing: sbctl; dot apply --packages")
        (row g/broken [] --error "plan: boom")
        (row g/broken-nopkg [] --error "plan: no tool yet" --pending "packages missing: tool; dot apply --packages")
        (row g/uses-nopkg [g/nopkg] --deps [g/nopkg])
        (row g/uses-broken [g/broken] --deps [g/broken])
        (row g/chain [g/uses-nopkg] --deps [g/uses-nopkg])
        (row g/uses-fine [g/fine] --deps [g/fine])
        # a group order alone, no dependency: runs even after a failure
        (row h/ordered [g/broken g/nopkg])
    ]
    let failures = mktemp --tmpdir dot-pipeline-test-XXXXXX
    let results = with-env {FAILURES_FILE: $failures} { pipeline-apply {platform: {}} $planned link 2 } | reduce --fold {} {|r, acc| $acc | insert $r.id $r }
    # one line per failed module, the dependents of a failure pending, not failed
    let lines = open --raw $failures | lines
    rm --force $failures
    # a held module that also failed to evaluate reports both
    if ($lines | sort) != ["g/broken link/eval: plan: boom" "g/broken-nopkg link/eval: plan: no tool yet"] { fail $"FAILURES lines: ($lines | to nuon)" }
    let cases = [
        [id ok pending];
        [g/fine true false]
        [g/nopkg true true]
        [g/broken false false]
        [g/broken-nopkg false true]
        [g/uses-nopkg true true]
        [g/uses-broken true true]
        [g/chain true true]
        [g/uses-fine true false]
        [h/ordered true false]
    ]
    for c in $cases {
        let r = $results | get --optional $c.id
        if $r == null { fail $"apply ($c.id): no result" }
        if $r.ok != $c.ok or ($r.pending != null) != $c.pending {
            fail $"apply ($c.id): ok ($r.ok) pending ($r.pending | to nuon), wants ok ($c.ok) pending ($c.pending)"
        }
    }
}

# A real module dir: hang leaves a setsid'd grandchild (its pid in a file) and blocks; mark touches a file; its link
# verb blocks when evaluated with hang = true.
const FAKE_MODULE = 'use module.nu *
export def link [cfg: record] { if $cfg.hang { ^sleep 300 }; [] }
export def hang [pidfile: string] { ^sh -c $"setsid sleep 300 & echo $! > ($pidfile); sleep 300" }
export def mark [file: string] { touch $file }
export def refuse [code: string] { error make {msg: $"git fetch of https://example.invalid failed: fatal: unable to access: The requested URL returned error: ($code)"} }
'
const STEP_BOUND = 2sec
const EVAL_BOUND = 3sec
# the bound, TERM's grace, then the scheduler's poll: a hung step returns well within this
const STEP_WAIT_MAX = 15sec

def fake-module [work: path, name: string]: nothing -> path {
    let dir = $work | path join $name
    mkdir $dir
    $FAKE_MODULE | save --force ($dir | path join mod.nu)
    $dir
}

def native-row [id: string, dir: path, actions: list<record>, --deps: list<string> = []]: nothing -> record {
    {
        id: $id, dir: $dir, after: $deps, deps: $deps, level: 0, serial: false, cfg: {}, options: {}, force: false
        native: true, skipped: false, input: "input", prev: [], actions: $actions, error: null, pending: null
    }
}

def step-action [id: string, decl: record]: nothing -> record {
    {module: $id, kind: step, target: $decl.target, reason: "", decl: $decl, before: null, after: null}
}

def apply-native [work: path, rows: list<record>, probe: string]: nothing -> record {
    let failures = $work | path join failures
    "" | save --force $failures
    let results = with-env {FAILURES_FILE: $failures, XDG_STATE_HOME: ($work | path join state), DOT_NETWORK_PROBE_URL: $probe, DOT_RUN_ID: ""} {
        pipeline-apply {platform: {facts: {homelab: false}}, layer: user, repo: $work} $rows link 2
    }
    {results: ($results | reduce --fold {} {|r, acc| $acc | insert $r.id $r }), failures: (open --raw $failures | lines)}
}

def pid-alive [pid: string]: nothing -> bool { ($"/proc/($pid)" | path exists) }

def step-timeout-cases [work: path]: nothing -> nothing {
    let dir = fake-module $work timeout
    let pidfile = $work | path join grandchild.pid
    let start = date now
    let run = apply-native $work [(native-row t/hang $dir [(step-action t/hang (step hang $pidfile --timeout $STEP_BOUND))])] "file:///"
    let took = (date now) - $start
    let r = $run.results | get t/hang
    if $took > $STEP_WAIT_MAX { fail $"step timeout: returned after ($took), wants within ($STEP_WAIT_MAX)" }
    if $r.ok { fail "step timeout: a hung step counted ok" }
    let wants = $"timed out after ($STEP_BOUND)"
    if not ($r.error | str contains $wants) { fail $"step timeout: error ($r.error | to nuon), wants it to say ($wants)" }
    if (cause-hint $r.error | get --optional class) != "timeout" { fail $"step timeout: ($r.error | to nuon) is no timeout class in HINTS" }
    if ($run.failures | length) != 1 or not ($run.failures.0 | str starts-with "t/hang link/step hang: ") {
        fail $"step timeout: FAILURES lines ($run.failures | to nuon)"
    }
    let pid = try { open --raw $pidfile | str trim } catch { "" }
    if $pid == "" { fail "step timeout: the step never started its grandchild" }
    if (pid-alive $pid) { ^kill -KILL $pid; fail $"step timeout: the setsid'd grandchild ($pid) outlived the timeout" }
}

def network-cases [work: path]: nothing -> nothing {
    let dir = fake-module $work network
    let marker = $work | path join downloaded
    let reachable = $work | path join reachable
    touch $reachable
    let rows = [
        (native-row n/fetch $dir [(step-action n/fetch (step mark $marker --network))])
        (native-row n/uses $dir [] --deps [n/fetch])
    ]
    let offline = apply-native $work $rows $"file://($work)/unreachable"
    let fetch = $offline.results | get n/fetch
    if not $fetch.ok or $fetch.pending != $OFFLINE_PENDING { fail $"network offline: ok ($fetch.ok) pending ($fetch.pending | to nuon), wants ok and ($OFFLINE_PENDING)" }
    if ($marker | path exists) { fail "network offline: the step ran without the network" }
    if ($offline.failures | is-not-empty) { fail $"network offline: FAILURES lines ($offline.failures | to nuon)" }
    let uses = $offline.results | get n/uses
    if $uses.pending != "waits on n/fetch (pending)" { fail $"network offline: the dependent's pending is ($uses.pending | to nuon)" }
    let lines = pending-lines [] [n/fetch n/uses] ($offline.results | values) true
    if $lines != [$"n/fetch: ($OFFLINE_PENDING)" "n/uses: waits on n/fetch (pending)"] { fail $"network offline: pending lines ($lines | to nuon)" }
    let recorded = open ($work | path join state dotfiles modules n fetch link.nuon)
    if $recorded.input != "" { fail "network offline: the module recorded its input, the next apply would skip it" }
    let online = apply-native $work $rows $"file://($reachable)"
    let fetch = $online.results | get n/fetch
    if not $fetch.ok or $fetch.pending != null { fail $"network online: ok ($fetch.ok) pending ($fetch.pending | to nuon), wants ok, not pending" }
    if not ($marker | path exists) { fail "network online: the step did not run" }
    if ($online.results | get n/uses | get pending) != null { fail "network online: the dependent still waits" }
}

def remote-pending-cases []: nothing -> nothing {
    let cases = [
        [name error wants];
        ["git 503" "fatal: unable to access 'https://x/': The requested URL returned error: 503" "the remote answered 503, retried on the next apply"]
        ["rate limit" "curl: (22) The requested URL returned error: 429" "the remote answered 429, retried on the next apply"]
        ["rust client" "Caused by: http status: 502" "the remote answered 502, retried on the next apply"]
        ["uv" "HTTP status server error, status code 503 Service Unavailable" "the remote answered 503, retried on the next apply"]
        ["wget" "ERROR 504: Gateway Time-out." "the remote answered 504, retried on the next apply"]
        ["dns" "fatal: unable to access 'https://x/': Could not resolve host: x" "the remote did not resolve, retried on the next apply"]
        ["gone" "Caused by: http status: 404" null]
        ["forbidden" "The requested URL returned error: 403" null]
        ["own failure" "blender -c extension build exited 1" null]
        ["a 500 elsewhere" "wrote 5030 bytes" null]
    ]
    for c in $cases {
        let got = remote-pending $c.error
        if $got != $c.wants { fail $"remote pending ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}

def requires-cases [work: path]: nothing -> nothing {
    let dir = fake-module $work requires
    let source = $work | path join fetched
    let marker = $work | path join built
    let rows = [(native-row r/build $dir [(step-action r/build (step mark $marker --requires $source))])]
    let absent = apply-native $work $rows "file:///"
    let build = $absent.results | get r/build
    let wants = $"waits on ($source), not there yet"
    if not $build.ok or $build.pending != $wants { fail $"requires absent: ok ($build.ok) pending ($build.pending | to nuon), wants ok and ($wants | to nuon)" }
    if ($marker | path exists) { fail "requires absent: the step ran without what it requires" }
    if ($absent.failures | is-not-empty) { fail $"requires absent: FAILURES lines ($absent.failures | to nuon)" }
    touch $source
    let present = apply-native $work $rows "file:///"
    if ($present.results | get r/build | get pending) != null or not ($marker | path exists) { fail "requires present: the step did not run" }
}

def remote-cases [work: path]: nothing -> nothing {
    let dir = fake-module $work remote
    let reachable = $work | path join reachable-remote
    touch $reachable
    let rows = [
        (native-row m/outage $dir [(step-action m/outage (step refuse "503" --network))])
        (native-row m/gone $dir [(step-action m/gone (step refuse "404" --network))])
        (native-row m/local $dir [(step-action m/local (step refuse "503"))])
    ]
    let run = apply-native $work $rows $"file://($reachable)"
    let outage = $run.results | get m/outage
    if not $outage.ok or $outage.pending != "the remote answered 503, retried on the next apply" {
        fail $"remote outage: ok ($outage.ok) pending ($outage.pending | to nuon), wants ok and pending on the 503"
    }
    if ($run.results | get m/gone | get ok) { fail "remote gone: a 404 counted as the remote's outage" }
    if ($run.results | get m/local | get ok) { fail "remote local: a step without --network turned its 503 into pending" }
    let subjects = $run.failures | each { split row " " | first } | sort
    if $subjects != [m/gone m/local] { fail $"remote: FAILURES lines ($run.failures | to nuon), wants m/gone and m/local only" }
}

def eval-timeout-cases [work: path]: nothing -> nothing {
    let fine = fake-module $work eval-fine
    let hung = fake-module $work eval-hung
    let mods = [{id: e/fine, dir: $fine} {id: e/hung, dir: $hung}]
    let cfgs = {e/fine: {hang: false}, e/hung: {hang: true}}
    let results = with-env {XDG_STATE_HOME: ($work | path join state)} { modules-eval $mods link $cfgs [] --timeout $EVAL_BOUND }
        | reduce --fold {} {|r, acc| $acc | insert $r.id $r }
    if not ($results | get e/fine | get ok) { fail $"eval timeout: the module that returns failed: ($results | get e/fine | get error)" }
    let r = $results | get e/hung
    let wants = $"evaluating link timed out after ($EVAL_BOUND)"
    if $r.ok or $r.error != $wants { fail $"eval timeout: ok ($r.ok) error ($r.error | to nuon), wants ($wants | to nuon)" }
}

def main [] {
    let work = mktemp --directory --tmpdir dot-pipeline-test-XXXXXX
    gate-cases
    held-cases
    pending-lines-cases
    absent-cases $work
    alive-cases $work
    apply-cases
    step-timeout-cases $work
    network-cases $work
    remote-pending-cases
    requires-cases $work
    remote-cases $work
    eval-timeout-cases $work
    rm --recursive --force $work
}
