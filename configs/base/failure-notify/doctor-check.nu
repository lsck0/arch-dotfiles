#!/usr/bin/env -S nu --no-config-file
# dot doctor on a timer: its FAIL lines go to a state file the bar's doctor indicator shows while it is not empty, and
# to one notification each time they turn into a set not notified before. a healthy machine stays silent

const DOT = path self | path expand | path dirname | path join ../../../scripts/dot.nu | path expand
const SHOWN_LINES = 5
const SHOWN_WIDTH = 160

def main []: nothing -> nothing {
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join doctor
    mkdir $state
    let run = ^nu --no-config-file $DOT doctor --brief | complete
    print --stderr --no-newline $run.stderr
    # 1 is "found something"; anything else is doctor itself failing, which OnFailure= reports
    if $run.exit_code > 1 { exit $run.exit_code }
    $run.stdout | save --force ($state | path join findings)
    let findings = $run.stdout | lines
    # ages, counts and times change every run; only a different finding is news
    let digest = $findings | str replace --all --regex '[0-9]+' N | str join "\n" | hash sha256
    let notified = $state | path join notified
    if $digest == (try { open --raw $notified | str trim } catch { "" }) { return }
    if ($findings | is-not-empty) {
        let body = $findings | first $SHOWN_LINES | str substring 0..<$SHOWN_WIDTH | append "dot doctor shows them all"
        # not shown (no notification daemon yet): not recorded, the next run tries again
        let title = $"Doctor: ($findings | length) findings"
        if (^notify-send -a doctor -u normal $title ($body | str join "\n") | complete).exit_code != 0 { return }
    }
    $digest | save --force $notified
}
