#!/usr/bin/env -S nu --no-config-file
# The exit of each dot apply branch: its run sets DOT_SYSTEM_PENDING inside the guarded closure (or the --packages pass
# before it), and apply-finish, called in that closure, turns it into exit 3; a failure is exit 1 first.
use state.nu [EXIT_PENDING]

const EXIT_FAILED = 1

def fail [msg: string] { error make {msg: $"run.test: ($msg)"} }

def main [] {
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
            fail $"($c.name): exit ($run.exit_code), wants ($c.wants)\n($run.stdout)($run.stderr)"
        }
    }
    rm --recursive --force $state
}
