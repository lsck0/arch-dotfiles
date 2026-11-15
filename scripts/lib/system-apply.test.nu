#!/usr/bin/env -S nu --no-config-file
# The install pass's resolution against a fake pacman -Sp: a repo of name -> dependencies, answering as pacman does
# (every unknown target and nothing else, else every unsatisfied dependency with who needs it). A name the mirror lacks
# waits only while no build could carry it yet; one root entry's exit follows its steps; and no argument of the entry is
# evaluated as code before its commands run.
use system-apply.nu [sync-errors-parse packages-resolve mirror-awaited stages-exit secrets-refused]
use state.nu [EXIT_ABORTED EXIT_PENDING]
use modules.nu [modules-packages]
use std/assert

const EXTRA_UNRESOLVABLE = "lsck0-vm-test-unresolvable"
const REPO_DB = {
    bash: []
    git: [bash]
    bugwarrior: [python python-lockfile]
    python: []
    taskwarrior-tui: [task]
    task: [libtask]
    libtask: [python-lockfile]
    zsh: []
}

def fake-sp [targets: list<string>]: nothing -> record {
    let unknown = $targets | where $it not-in ($REPO_DB | columns)
    if ($unknown | is-not-empty) {
        return {ok: false, output: ($unknown | each { $"error: target not found: ($in)" })}
    }
    mut todo = $targets
    mut seen = []
    mut broken = []
    while ($todo | is-not-empty) {
        let name = $todo | first
        $todo = $todo | skip 1
        if $name in $seen { continue }
        $seen = $seen | append $name
        for dep in ($REPO_DB | get $name) {
            if $dep in ($REPO_DB | columns) { $todo = $todo | append $dep } else { $broken = $broken | append {dep: $dep, by: $name} }
        }
    }
    if ($broken | is-empty) { return {ok: true, output: $seen} }
    let warnings = $broken | each { $"warning: cannot resolve \"($in.dep)\", a dependency of \"($in.by)\"" }
    let colon = $broken | each { $":: unable to satisfy dependency '($in.dep)' required by ($in.by)" }
    {ok: false, output: ($warnings ++ ["error: failed to prepare transaction (could not satisfy dependencies)"] ++ $colon)}
}

def parse-cases []: nothing -> nothing {
    let out = [
        "error: target not found: nonexistent"
        "warning: cannot resolve \"python-lockfile\", a dependency of \"bugwarrior\""
        "error: failed to prepare transaction (could not satisfy dependencies)"
        ":: unable to satisfy dependency 'python-lockfile>=0.12' required by bugwarrior"
    ]
    let got = sync-errors-parse $out
    assert equal $got.not_found [nonexistent] $"parse not_found: ($got.not_found | to nuon)"
    assert equal $got.unsatisfied [{dep: "python-lockfile>=0.12", by: bugwarrior}] $"parse unsatisfied: ($got.unsatisfied | to nuon)"
}

def resolve-cases []: nothing -> nothing {
    let filler = [bash git python zsh]
    let cases = [
        [name targets kept dropped];
        [clean $filler $filler []]
        ["not found next to a resolvable one" [nonexistent bash] [bash] [nonexistent]]
        ["declared one needs a missing dependency" [bugwarrior bash] [bash] [bugwarrior]]
        ["only a transitive dependency misses one" ([taskwarrior-tui] ++ $filler) $filler [taskwarrior-tui]]
        ["all at once" ([nonexistent bugwarrior taskwarrior-tui] ++ $filler) $filler [nonexistent bugwarrior taskwarrior-tui]]
        ["nothing resolves" [nonexistent] [] [nonexistent]]
    ]
    for c in $cases {
        let r = packages-resolve $c.targets {|t| fake-sp $t }
        assert equal $r.kept $c.kept $"resolve ($c.name): kept ($r.kept | to nuon), wants ($c.kept | to nuon)"
        if ($r.dropped.name? | default [] | sort) != ($c.dropped | sort) {
            error make {msg: $"resolve ($c.name): dropped ($r.dropped | to nuon), wants ($c.dropped | to nuon)"}
        }
        assert not ($r.dropped | any { $in.why | is-empty }) $"resolve ($c.name): a drop without its reason"
    }
    # an error of another kind (a conflict) drops nothing: the install pass reports it
    let stuck = packages-resolve [bash] {|t| {ok: false, output: ["error: unresolvable package conflicts detected"]} }
    assert equal $stuck {kept: [bash], dropped: []} $"resolve conflict: ($stuck | to nuon)"
}

# the platform's extra_packages reach the pass in the same list as the modules', so one that does not resolve drops alone
def extra-cases []: nothing -> nothing {
    let module = {
        id: g/m, dir: "/nonexistent", native: [], selected: true, broken: false, cfg: {enable: true}
        meta: {deps: [], packages: {pacman: [git], native: [], flatpak: {}, nix: []}, serial: false}
    }
    let platform = {form_factor: desktop, extra_packages: [$EXTRA_UNRESOLVABLE zsh]}
    let declared = modules-packages "/nonexistent" [$module] $platform
    assert ($EXTRA_UNRESOLVABLE in $declared.pacman) $"extra_packages not declared: ($declared.pacman | to nuon)"
    let r = packages-resolve $declared.pacman {|t| fake-sp $t }
    assert equal $r.dropped.name [$EXTRA_UNRESOLVABLE] $"extra dropped: ($r.dropped | to nuon)"
    assert equal ($r.kept | sort) [git zsh] $"extra kept: ($r.kept | to nuon)"
}

def awaited-cases []: nothing -> nothing {
    let now = 2026-11-15T20:40:00+01:00
    let asked_before = "2026-11-14T16:00:00+01:00"
    let built = 2026-11-15T12:02:00+01:00
    let cases = [
        [name names recorded built awaited failed];
        ["first seen after the build" [new] [] $built [new] []]
        ["a build since the first ask still lacks it" [typo] [$"typo ($asked_before)"] $built [] [typo]]
        ["asked after the build, on a later run" [new] ["new 2026-11-15T20:21:00+01:00"] $built [new] []]
        ["no lsck0 database" [new] [] null [] [new]]
        ["one of each" [new typo] [$"typo ($asked_before)"] $built [new] [typo]]
        ["nothing lacking" [] [$"gone ($asked_before)"] $built [] []]
    ]
    for c in $cases {
        let got = mirror-awaited $c.names $c.recorded $c.built $now
        assert equal $got.awaited $c.awaited $"awaited ($c.name): ($got | to nuon)"
        assert equal $got.failed $c.failed $"awaited ($c.name): failed ($got | to nuon)"
        assert equal ($got.record | each { split row " " | first }) $c.names $"awaited ($c.name): records ($got.record | to nuon)"
    }
    # the first ask is kept, so a later build can outdate it
    let kept = mirror-awaited [typo] [$"typo ($asked_before)"] null $now
    assert equal $kept.record [$"typo ($asked_before)"] $"awaited: the first ask moved: ($kept.record | to nuon)"
}

def exit-cases []: nothing -> nothing {
    let cases = [
        [codes wants];
        [[0 0 0] 0]
        [[$EXIT_PENDING 0 0] $EXIT_PENDING]
        [[0 0 $EXIT_PENDING] $EXIT_PENDING]
        [[1 0 $EXIT_PENDING] 1]
        [[0 1 0] 1]
        [[$EXIT_ABORTED] $EXIT_ABORTED]
        [[0 130] 1]
    ]
    for c in $cases { assert equal (stages-exit $c.codes) $c.wants $"exit of ($c.codes | to nuon)" }
}

# nu builds the call of a script's main from its argv: a --wrapped main gets `--flag=(expr)` evaluated before its body,
# which for root's entry would run a caller's expression as root. Every command of the entry, with an expression in
# each argument shape, must leave the marker unwritten (the commands themselves stop at repo-guard here).
def argv-cases []: nothing -> nothing {
    let entry = $env.FILE_PWD | path join system-apply.nu
    let wrapped = open --raw $entry | lines | where $it =~ '^\s*(export )?def .*--wrapped.*\bmain\b'
    assert ($wrapped | is-empty) $"system-apply.nu has a --wrapped main: ($wrapped | to nuon)"
    let dir = mktemp --directory --tmpdir system-apply-argv-XXXXXX
    let marker = $dir | path join evaluated
    let expr = $"\(touch ($marker); true\)"
    let sha = "0123456789abcdef0123456789abcdef01234567"
    let calls = [
        [$"--force=($expr)"]
        [apply $sha config $"--force=($expr)"]
        [apply $sha config $"--unattended=($expr)" $"--yes=($expr)"]
        [apply $sha config --run $expr]
        [apply $sha config $"--run=($expr)"]
        [apply $expr $expr]
        [install $"--unattended=($expr)" $"--yes=($expr)"]
        [config $"--unattended=($expr)" $"--force=($expr)"]
        [packages $"--yes=($expr)" $"--plan=($expr)"]
        [module $expr]
        [migrate $"--baseline=($expr)"]
        [preserve-prune $expr]
        [adduser $expr $"--profile=($expr)"]
    ]
    for call in $calls {
        let run = ^$nu.current-exe --no-config-file $entry ...$call | complete
        let evaluated = $marker | path exists
        if $evaluated { rm --recursive --force $dir }
        assert (not $evaluated) $"argv: ($call | str join ' ') was evaluated before the command ran"
        assert ($run.exit_code != 0) $"argv: ($call | str join ' ') ran as a user, exit 0"
    }
    rm --recursive --force $dir
}

def secrets-cases []: nothing -> nothing {
    let allowed = [token wg/lab.conf]
    let cases = [
        [name handed refused];
        ["only what is declared" [{name: token, type: file} {name: wg/lab.conf, type: file}] []]
        ["an undeclared file" [{name: token, type: file} {name: ssh/id, type: file}] [ssh/id]]
        ["a link under a declared name" [{name: token, type: symlink}] [token]]
        ["a fifo" [{name: wg/lab.conf, type: fifo}] [wg/lab.conf]]
        ["a declared name's sibling" [{name: wg/other.conf, type: file}] [wg/other.conf]]
        ["nothing handed" [] []]
    ]
    for c in $cases { assert equal (secrets-refused $c.handed $allowed) $c.refused $"secrets ($c.name)" }
    assert equal (secrets-refused [{name: token, type: file}] []) [token] "secrets: with nothing declared a file is kept"
}

def main [] {
    secrets-cases
    awaited-cases
    exit-cases
    argv-cases
    parse-cases
    resolve-cases
    extra-cases
}
