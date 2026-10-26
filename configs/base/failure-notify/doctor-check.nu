#!/usr/bin/env -S nu --no-config-file

const DOT = path self | path expand | path dirname | path join ../../../scripts/dot.nu | path expand
const SHOWN_LINES = 5
const SHOWN_WIDTH = 160

def main []: nothing -> nothing {
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join doctor
    mkdir $state
    let run = ^nu --no-config-file $DOT status --brief | complete
    print --stderr --no-newline $run.stderr
    # 1 means findings, but guarded also exits 1 on a crash: findings always print a line, a crash prints none
    if $run.exit_code > 1 or ($run.exit_code == 1 and ($run.stdout | str trim | is-empty)) {
        exit ([$run.exit_code 1] | math max)
    }
    $run.stdout | save --force ($state | path join findings)
    let findings = $run.stdout | lines
    let digest = $findings | str replace --all --regex '[0-9]+' N | str join "\n" | hash sha256
    let notified = $state | path join notified
    if $digest == (try { open --raw $notified | str trim } catch { "" }) { return }
    if ($findings | is-not-empty) {
        let body = $findings | first $SHOWN_LINES | str substring 0..<$SHOWN_WIDTH | append "dot status shows them all"
        # no notification daemon yet: unrecorded, so the next run tries again
        let title = $"Doctor: ($findings | length) findings"
        if (^notify-send -a doctor -u normal $title ($body | str join "\n") | complete).exit_code != 0 { return }
    }
    $digest | save --force $notified
}
