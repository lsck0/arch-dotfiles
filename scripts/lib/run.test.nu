#!/usr/bin/env -S nu --no-config-file
# The exit of each dot apply branch: its run sets DOT_SYSTEM_PENDING inside the guarded closure (or the --packages pass
# before it), and apply-finish, called in that closure, turns it into exit 3; a failure is exit 1 first. What
# failures-publish leaves of earlier FAILURES lines after a partial, a full and a clean run.
use state.nu [EXIT_PENDING]
use run.nu [failures-publish]
use std/assert

const EXIT_FAILED = 1

const USER_LINE = "a/mod link/step: user broke"
const SYSTEM_LINE = "a/mod system/step: system broke"
const OTHER_LINE = "b/other link/step: other broke"
const PASSED = [{id: a/mod, ok: true, pending: null}]

def publish-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-run-publish-XXXXXX
    let published = $dir | path join FAILURES.config
    let own = $dir | path join run.failures
    let earlier = [$USER_LINE $SYSTEM_LINE $OTHER_LINE]
    let cases = [
        [name full system_ran results new wants];
        ["partial keeps a passed module's system line" false false $PASSED [] [$SYSTEM_LINE $OTHER_LINE]]
        ["partial with the system layer clears the module" false true $PASSED [] [$OTHER_LINE]]
        ["partial adds a new failure" false false [{id: c/new, ok: false, pending: null}] ["c/new link/step: new"] [...$earlier "c/new link/step: new"]]
        ["full user-only keeps only system lines" true false $PASSED [] [$SYSTEM_LINE]]
        ["full clean run removes the file" true true $PASSED [] null]
    ]
    for c in $cases {
        $"($earlier | str join "\n")\n" | save --force $published
        $c.new | each { $"($in)\n" } | str join | save --force $own
        let env_run = {DOT_FAILURES_OWNED: true, FAILURES_FILE: $own, DOT_FULL_RUN: $c.full, DOT_SYSTEM_RAN: $c.system_ran, DOT_RUN_ID: test}
        let ok = with-env $env_run { failures-publish $c.results $published }
        assert equal $ok ($c.new | is-empty) $"publish ($c.name): returned ($ok)"
        let got = if ($published | path exists) { open --raw $published | lines } else { null }
        assert equal $got $c.wants $"publish ($c.name): left ($got | to nuon)"
    }
    rm --recursive --force $dir
}

def main [] {
    publish-cases
    let state = mktemp --directory --tmpdir dot-run-test-XXXXXX
    let src = "use cli.nu [guarded]; use run.nu [apply-finish]
def --env run-held [] { $env.DOT_SYSTEM_PENDING = true; [{id: t/held, ok: true, pending: 'packages missing: x', outcomes: [], log: ''}] }
def --env run-clean [] { [{id: t/clean, ok: true, pending: null, outcomes: [], log: ''}] }
def --env run-failed [] { $env.DOT_SYSTEM_PENDING = true; [{id: t/failed, ok: false, pending: null, outcomes: [], log: ''}] }
"
    # each branch's shape in dot.nu's main apply, the run standing in for link-run or apply-run
    let cases = [
        [name call wants];
        ["a module held" "guarded apply --read-only { run-held | apply-finish $in }" $EXIT_PENDING]
        ["nothing held" "guarded apply --read-only { run-clean | apply-finish $in }" 0]
        ["after --packages left something pending" "$env.DOT_SYSTEM_PENDING = true; guarded apply --read-only { run-clean | apply-finish $in }" $EXIT_PENDING]
        ["a failure wins over pending" "guarded apply --read-only { run-failed | apply-finish $in }" $EXIT_FAILED]
    ]
    for c in $cases {
        let run = with-env {XDG_STATE_HOME: $state, FAILURES_FILE: null} { ^$nu.current-exe --no-config-file -I ($env.FILE_PWD) -c $"($src)($c.call)" | complete }
        if $run.exit_code != $c.wants {
            rm --recursive --force $state
            error make {msg: $"($c.name): exit ($run.exit_code), wants ($c.wants)\n($run.stdout)($run.stderr)"}
        }
    }
    rm --recursive --force $state
}
