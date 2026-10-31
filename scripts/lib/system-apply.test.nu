#!/usr/bin/env -S nu --no-config-file
# The install pass's resolution against a fake pacman -Sp: a repo of name -> dependencies, answering as pacman does
# (every unknown target and nothing else, else every unsatisfied dependency with who needs it).
use system-apply.nu [sync-errors-parse packages-resolve]
use modules.nu [modules-packages]

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

def fail [msg: string] { error make {msg: $"system-apply.test: ($msg)"} }

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
    if $got.not_found != [nonexistent] { fail $"parse not_found: ($got.not_found | to nuon)" }
    if $got.unsatisfied != [{dep: "python-lockfile>=0.12", by: bugwarrior}] { fail $"parse unsatisfied: ($got.unsatisfied | to nuon)" }
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
        if $r.kept != $c.kept { fail $"resolve ($c.name): kept ($r.kept | to nuon), wants ($c.kept | to nuon)" }
        if ($r.dropped.name? | default [] | sort) != ($c.dropped | sort) {
            fail $"resolve ($c.name): dropped ($r.dropped | to nuon), wants ($c.dropped | to nuon)"
        }
        if ($r.dropped | any { $in.why | is-empty }) { fail $"resolve ($c.name): a drop without its reason" }
    }
    # an error of another kind (a conflict) drops nothing: the install pass reports it
    let stuck = packages-resolve [bash] {|t| {ok: false, output: ["error: unresolvable package conflicts detected"]} }
    if $stuck != {kept: [bash], dropped: []} { fail $"resolve conflict: ($stuck | to nuon)" }
}

# the platform's extra_packages reach the pass in the same list as the modules', so one that does not resolve drops alone
def extra-cases []: nothing -> nothing {
    let module = {
        id: g/m, dir: "/nonexistent", native: [], selected: true, broken: false, cfg: {enable: true}
        meta: {deps: [], packages: {pacman: [git], native: [], flatpak: {}, nix: []}, serial: false}
    }
    let platform = {form_factor: desktop, extra_packages: [$EXTRA_UNRESOLVABLE zsh]}
    let declared = modules-packages "/nonexistent" [$module] $platform
    if $EXTRA_UNRESOLVABLE not-in $declared.pacman { fail $"extra_packages not declared: ($declared.pacman | to nuon)" }
    let r = packages-resolve $declared.pacman {|t| fake-sp $t }
    if $r.dropped.name != [$EXTRA_UNRESOLVABLE] { fail $"extra dropped: ($r.dropped | to nuon)" }
    if ($r.kept | sort) != [git zsh] { fail $"extra kept: ($r.kept | to nuon)" }
}

def main [] {
    parse-cases
    resolve-cases
    extra-cases
}
