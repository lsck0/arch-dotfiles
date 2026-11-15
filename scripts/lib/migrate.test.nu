#!/usr/bin/env -S nu --no-config-file
# Migrations: a layer's first run on a machine baselines every one without running it, later ones run once and are
# recorded, a failing one stays pending, and each layer sees only its own. Baselining a machine that is not fresh
# would skip changes it still needs, so a layer once initialised never baselines again.
use migrate.nu [migrations-run migrations-pending]
use ledger.nu [ledger-get ledger-set]
use std/assert

def migration [repo: path, id: string, body: string, --system]: nothing -> nothing {
    let layer = if $system { "export const layer = \"system\"\n" } else { "" }
    $"($layer)export def up [] { ($body) }\n" | save --force ($repo | path join migrations $"($id).nu")
}

def ran [work: path]: nothing -> list<string> {
    glob ($work | path join "ran-*") | path basename | sort
}

def check [work: path]: nothing -> nothing {
    let repo = $work | path join repo
    mkdir ($repo | path join migrations)
    let touch = {|name: string| $"touch ($work | path join $'ran-($name)' | to nuon)" }
    migration $repo 0001-first (do $touch first)
    migration $repo 0002-root (do $touch root) --system
    "not a migration\n" | save ($repo | path join migrations notes.nu)

    assert equal (migrations-pending $repo user | get id) [0001-first] "pending: the user layer's own, a stray file left out"
    assert equal (migrations-pending $repo system | get id) [0002-root] "pending: the system layer's own"
    assert equal (migrations-run $repo user) [0001-first] "a fresh layer returns what it baselined"
    assert equal (ran $work) [] "a fresh layer ran a migration instead of baselining it"
    assert equal (ledger-get migration) [0001-first] "the baseline is not recorded"
    assert ("user" in (ledger-get initialised)) "the layer is not marked initialised"
    assert equal (migrations-run $repo user) [] "a second run found something pending"

    migration $repo 0003-later (do $touch later)
    assert equal (migrations-run $repo user) [0003-later] "a later migration is not pending"
    assert equal (ran $work) [ran-later] "a later migration did not run"
    assert equal (migrations-run $repo user) [] "a migration ran twice"

    migration $repo 0004-broken "error make {msg: broken}"
    migration $repo 0005-after (do $touch after)
    let failed = try { migrations-run $repo user | ignore; false } catch { true }
    assert $failed "a failing migration did not stop the run"
    assert equal (ledger-get migration) [0001-first 0003-later] "a failing migration, or one after it, is recorded"
    assert equal (ran $work) [ran-later] "a migration after the failing one ran"

    migration $repo 0004-broken (do $touch mended)
    assert equal (migrations-run $repo user --baseline) [0004-broken 0005-after] "--baseline returns what it marked"
    assert equal (ran $work) [ran-later] "--baseline ran a migration"

    # an initialised layer whose migration record was lost is no fresh machine
    ledger-set migration []
    assert equal (migrations-run $repo user) [0001-first 0003-later 0004-broken 0005-after] "an initialised layer baselined again"
    assert equal (ran $work) [ran-after ran-first ran-later ran-mended] "an initialised layer skipped its migrations"
}

def main []: nothing -> nothing {
    let work = mktemp --directory --tmpdir dot-migrate-test-XXXXXX
    let outcome = try {
        with-env {XDG_STATE_HOME: ($work | path join state), DOT_LAYER: user, DOT_RUN_ID: "", DOT_RUN_FILE: "", FAILURES_FILE: ""} { check $work }
        null
    } catch {|e| $e }
    rm --recursive --force $work
    if $outcome != null { error make $outcome }
}
