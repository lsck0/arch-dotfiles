#!/usr/bin/env -S nu --no-config-file
# zshrc's sudo-at-terminal refuses an agent and a caller without a terminal, and lets a person through. A fake sudo
# stands in for the real one; the script refuses to run unless the guard would reach the fake.

const HERE = path self | path dirname
const RAN = "fake sudo ran"
const REFUSED = "needs root"
const AGENT_MARKERS = [CLAUDECODE AI_AGENT GEMINI_CLI COPILOT_CLI_BINARY_VERSION]
const WRONG_SUDO_EXIT = 99

def guard-text []: nothing -> string {
    let lines = open --raw ($HERE | path join zshrc) | lines
    let first = $lines | enumerate | where ($it.item | str starts-with "sudo-at-terminal()") | get 0.index
    let last = $lines | enumerate | skip ($first + 1) | where ($it.item | str starts-with "}") | get 0.index
    $lines | slice $first..$last | str join "\n"
}

def guard-run [dir: path, markers: list<string>, --tty]: nothing -> record {
    let fake = $dir | path join sudo
    let script = $dir | path join guard.zsh
    $"(guard-text)\nhash sudo=($fake)\n[[ ${commands[sudo]} == ($fake) ]] || exit ($WRONG_SUDO_EXIT)\nsudo-at-terminal true\n"
    | save --force $script
    let unset = $AGENT_MARKERS | each {|m| [-u $m] } | flatten
    let set = $markers | each {|m| $"($m)=1" }
    let zsh = [env ...$unset ...$set $"PATH=($dir):/usr/bin" zsh -f $script]
    if $tty {
        ^script -qec ($zsh | str join " ") /dev/null | complete
    } else {
        ^sh -c 'exec "$@" </dev/null' sh ...$zsh | complete
    }
}

def main [] {
    let dir = mktemp -d
    "#!/bin/sh\necho 'fake sudo ran'\n" | save ($dir | path join sudo)
    ^chmod +x ($dir | path join sudo)
    let cases = [
        [name markers tty ran];
        ["no terminal" [] false false]
        ["agent at a terminal" [CLAUDECODE] true false]
        ["other agent at a terminal" [GEMINI_CLI] true false]
        ["person at a terminal" [] true true]
    ]
    let failures = $cases | each {|c|
        let r = if $c.tty { guard-run $dir $c.markers --tty } else { guard-run $dir $c.markers }
        let out = $r.stdout + $r.stderr
        if $r.exit_code == $WRONG_SUDO_EXIT {
            $"($c.name): sudo did not resolve to the fake, not run"
        } else if ($out | str contains $RAN) != $c.ran {
            $"($c.name): sudo ran is ($out | str contains $RAN), wants ($c.ran): ($out | str trim)"
        } else if not $c.ran and not ($out | str contains $REFUSED) {
            $"($c.name): no refusal message: ($out | str trim)"
        }
    } | compact
    rm -rf $dir
    if ($failures | is-not-empty) {
        print --stderr ($failures | str join "\n")
        exit 1
    }
}
