#!/usr/bin/env -S nu --no-config-file
# The packages a module's hook can want under every profile and option, which mirror/packages.txt is built from, and
# the run order's levels: group dependencies, a meta.deps edge to one specific module of another group, and a cycle.
# A discover cache that is missing, empty, cut off or of the wrong shape is a miss, never a crash; each checkout
# keeps its own, and a miss prunes those of removed checkouts. Root runs the hooks of system and packages modules, and
# a detect only where one of them reads its module.
use modules.nu [module-packages-every packages-every-context modules-graph modules-discover modules-root-run]
use std/assert

const HOOK_MODULE = "use profile.nu [profile-has]
export def packages [cfg: record]: nothing -> record {
    let owner = if (profile-has secrets) { [owner-tool] } else { [plain-tool] }
    let audio = if $cfg.audio == true { [audio-tool] } else { [] }
    {pacman: ($owner ++ $audio ++ [$\"driver-($cfg.driver)\" $\"port-($cfg.port)\"])}
}
"

# The packages every profile and option can want, the same whichever profile the caller runs under.
def packages-every-check [] {
    let repo = mktemp --directory --tmpdir dot-modules-test-XXXXXX
    mkdir ($repo | path join profiles) ($repo | path join platforms) ($repo | path join mod)
    {capabilities: [secrets]} | save ($repo | path join profiles owner.nuon)
    {"x/mod": {port: 2}} | save ($repo | path join platforms box.options.nuon)
    $HOOK_MODULE | save ($repo | path join mod mod.nu)
    let m = {
        id: x/mod, dir: ($repo | path join mod), native: [packages]
        meta: {packages: {pacman: [base-tool], native: [], flatpak: {}, nix: []}}
        options: {driver: {type: "string?", default: null, choices: [open legacy]}, port: {type: int, default: 1}, audio: {type: "bool?", default: null}}
        cfg: {enable: false, driver: legacy, port: 9, audio: null}
    }
    let every = packages-every-context $repo
    let as_owner = with-env {PROFILE_FILE: ($repo | path join profiles owner.nuon)} { module-packages-every $m $every }
    let as_nobody = with-env {PROFILE_FILE: "", XDG_CONFIG_HOME: ($repo | path join none)} { module-packages-every $m $every }
    rm --recursive --force $repo
    let wants = [audio-tool base-tool driver- driver-legacy driver-open owner-tool plain-tool port-1 port-2]
    assert equal ($as_owner | sort) $wants $"packages every: got ($as_owner | sort | to nuon), wants ($wants | to nuon)"
    assert equal $as_owner $as_nobody $"packages every: ($as_owner | to nuon) as the owner, ($as_nobody | to nuon) as nobody"
}

# Group dependencies (dependencies.txt, implicit base) set each module's level; a meta.deps edge reaches one module
# of another group without pulling its siblings along; root modules (group "") wait on every grouped module; a
# meta.deps cycle is caught.
def graph-cases [] {
    let repo = mktemp --directory --tmpdir dot-modules-test-XXXXXX
    mkdir ($repo | path join configs base) ($repo | path join configs mid) ($repo | path join configs top)
    "mid" | save ($repo | path join configs top dependencies.txt)
    let modules = [
        {id: base/a, group: base, meta: {deps: []}}
        {id: mid/a, group: mid, meta: {deps: []}}
        {id: mid/b, group: mid, meta: {deps: []}}
        {id: top/a, group: top, meta: {deps: []}}
        # beta reaches one mid module without a group-level dependencies.txt entry: only beta/a waits, not beta/b
        {id: beta/a, group: beta, meta: {deps: [mid/b]}}
        {id: beta/b, group: beta, meta: {deps: []}}
        {id: root/x, group: "", meta: {deps: []}}
    ]
    let levels = modules-graph $repo $modules | select id level | reduce --fold {} {|r, acc| $acc | insert $r.id $r.level }
    let wants = {base/a: 0, mid/a: 1, mid/b: 1, top/a: 2, beta/a: 2, beta/b: 1, root/x: 3}
    assert equal $levels $wants $"graph levels: got ($levels | to nuon), wants ($wants | to nuon)"
    rm --recursive --force $repo

    let cyclic = [{id: g/a, group: g, meta: {deps: [g/b]}} {id: g/b, group: g, meta: {deps: [g/a]}}]
    let repo = mktemp --directory --tmpdir dot-modules-test-XXXXXX
    mkdir ($repo | path join configs g)
    assert error { modules-graph $repo $cyclic } "graph: a meta.deps cycle is not caught"
    rm --recursive --force $repo
}

def discover-cache-cases [] {
    let work = mktemp --directory --tmpdir dot-modules-test-XXXXXX
    let repo = $work | path join repo
    mkdir ($repo | path join configs g m)
    "export def link [cfg: record] { [] }\n" | save ($repo | path join configs g m mod.nu)
    let caches = {|| glob ($work | path join cache dotfiles discover*.nuon) }
    let cases = [
        [name content];
        ["none" null]
        ["empty" ""]
        ["cut off" "{key: \"abc\", modules: [{id: "]
        ["a list" "[1 2]"]
    ]
    let discover_in = {|r| with-env {XDG_CACHE_HOME: ($work | path join cache)} { modules-discover $r [g] } }
    do $discover_in $repo
    let cache = do $caches | first
    for c in $cases {
        rm --force $cache
        if $c.content != null { $c.content | save $cache }
        let found = do $discover_in $repo
        assert equal $found.id [g/m] $"discover cache ($c.name): found ($found.id | to nuon)"
        assert equal (open $cache | get modules.id) [g/m] $"discover cache ($c.name): not written anew"
        assert equal (^stat -c "%a" $cache | str trim) "600" $"discover cache ($c.name): readable by others"
    }
    # a second checkout keeps its own cache; a miss prunes the one of a removed checkout and the older single cache
    let other = $work | path join other
    mkdir ($other | path join configs g n)
    "export def link [cfg: record] { [] }\n" | save ($other | path join configs g n mod.nu)
    assert equal (do $discover_in $other | get id) [g/n] "discover cache: the second checkout read the first's"
    assert equal (do $caches | length) 2 $"discover cache: checkouts share a file: (do $caches | to nuon)"
    assert equal (open $cache | get modules.id) [g/m] "discover cache: the second checkout overwrote the first's"
    let legacy = $work | path join cache dotfiles discover.nuon
    "{key: \"\", modules: []}" | save $legacy
    rm --recursive $other
    "export def link [cfg: record] { [ ] }\n" | save --force ($repo | path join configs g m mod.nu)
    do $discover_in $repo
    assert equal (do $caches) [$cache] $"discover cache: stale caches kept: (do $caches | to nuon)"
    let shared = $repo | path join configs g shared.nu
    "export const V = \"old\"\n" | save $shared
    "use ../shared.nu [V]\nexport const options = {v: {type: string, default: $V}}\nexport def link [cfg: record] { [] }\n"
        | save --force ($repo | path join configs g m mod.nu)
    let discover = {|| with-env {XDG_CACHE_HOME: ($work | path join cache)} { modules-discover $repo [g] } }
    assert equal (do $discover | get 0.options.v.default) old "discover cache: imported const not read"
    "export const V = \"newer\"\n" | save --force $shared
    assert equal (do $discover | get 0.options.v.default) newer "discover cache: a changed import served stale"
    rm --recursive --force $work
}

def root-run-cases [] {
    let row = {|id, native, meta = {deps: []}, broken = false| {id: $id, native: $native, meta: $meta, broken: $broken} }
    let modules = [
        (do $row a/system [system detect])
        (do $row a/packages [packages])
        (do $row a/link [link])
        (do $row a/sensed [detect link])
        (do $row a/dep [detect])
        (do $row a/read [detect])
        (do $row a/reader [system] {deps: [a/dep], reads: [a/read]})
        (do $row a/user [link] {deps: [a/sensed]})
        (do $row a/broken [] {deps: []} true)
    ]
    let got = modules-root-run $modules | sort
    assert equal $got [a/broken a/dep a/packages a/read a/reader a/system] $"root-run: got ($got | to nuon)"
}

def main [] {
    packages-every-check
    graph-cases
    discover-cache-cases
    root-run-cases
}
