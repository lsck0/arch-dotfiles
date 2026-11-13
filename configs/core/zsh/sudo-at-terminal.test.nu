#!/usr/bin/env -S nu --no-config-file
# zshrc's and config.nu's sudo-at-terminal refuse an agent and a caller without a terminal, and let a person through. A
# fake sudo stands in for the real one; each script refuses to run unless the guard would reach the fake. Both shells
# name the same agent markers as cli.nu.

const HERE = path self .
const ZSHRC = $HERE | path join zshrc
const CONFIG_NU = $HERE | path join .. nushell config.nu
const CLI_NU = $HERE | path join .. .. .. scripts lib cli.nu
const RAN = "fake sudo ran"
const REFUSED = "needs root"
const MARKERS_NU = "const AGENT_MARKERS"
const MARKERS_ZSH = "agent-session()"
const WRONG_SUDO_EXIT = 99

def line-starting [file: path, head: string]: nothing -> string {
    open --raw $file | lines | where ($it | str starts-with $head) | first
}

def markers-nu [file: path]: nothing -> list<string> {
    line-starting $file $MARKERS_NU | parse --regex '\[(?<names>[^\]]*)\]' | get 0.names | split row " "
}

def markers-zsh []: nothing -> list<string> {
    line-starting $ZSHRC $MARKERS_ZSH | parse --regex '\$\{(?<name>\w+)-\}' | get name
}

# The lines from the one starting with head through the next closing brace.
def block [lines: list<string>, head: string]: nothing -> list<string> {
    let first = $lines | enumerate | where ($it.item | str starts-with $head) | get 0.index
    let last = $lines | enumerate | skip ($first + 1) | where ($it.item | str starts-with "}") | get 0.index
    $lines | slice $first..$last
}

def zsh-script [fake: path]: nothing -> string {
    let guard = block (open --raw $ZSHRC | lines) "sudo-at-terminal()"
    [(line-starting $ZSHRC $MARKERS_ZSH) ...$guard $"hash sudo=($fake)" $"[[ ${commands[sudo]} == ($fake) ]] || exit ($WRONG_SUDO_EXIT)"] | str join "\n"
}

def nu-script [fake: path]: nothing -> string {
    let lines = open --raw $CONFIG_NU | lines
    let markers = line-starting $CONFIG_NU $MARKERS_NU
    let session = line-starting $CONFIG_NU "let agent_session"
    let guard = block $lines "def --wrapped sudo-at-terminal"
    [$markers $session ...$guard $"if \(which sudo | get 0.path\) != '($fake)' { exit ($WRONG_SUDO_EXIT) }"] | str join "\n"
}

# An alias resolves its command where it is declared, so one ahead of the def runs a missing external.
def alias-order-check []: nothing -> list<string> {
    let lines = open --raw $CONFIG_NU | lines | enumerate
    let def = $lines | where ($it.item | str starts-with "def --wrapped sudo-at-terminal") | get 0.index
    $lines | where ($it.item =~ '^alias .*= sudo-at-terminal ') and $it.index < $def | each {|l|
        $"config.nu line ($l.index + 1) runs sudo-at-terminal before its def: ($l.item)"
    }
}

def marker-parity-check [markers: list<string>]: nothing -> list<string> {
    [[name names]; [zshrc (markers-zsh)] [config.nu (markers-nu $CONFIG_NU)]]
    | where $it.names != $markers
    | each {|s| $"($s.name) names agent markers ($s.names | str join ' '), cli.nu ($markers | str join ' ')" }
}

def guard-run [dir: path, shell: record, markers: list<string>, all: list<string>, --tty]: nothing -> record {
    let script = $dir | path join $"guard.($shell.name)"
    $"(do $shell.script ($dir | path join sudo))\nsudo-at-terminal true\n" | save --force $script
    let unset = $all | each {|m| [-u $m] } | flatten
    let set = $markers | each {|m| $"($m)=1" }
    let argv = [env ...$unset ...$set $"PATH=($dir):/usr/bin" ...$shell.argv $script]
    if $tty {
        ^script -qec ($argv | str join " ") /dev/null | complete
    } else {
        ^sh -c 'exec "$@" </dev/null' sh ...$argv | complete
    }
}

def main [] {
    let all = markers-nu $CLI_NU
    let dir = mktemp -d
    "#!/bin/sh\necho 'fake sudo ran'\n" | save ($dir | path join sudo)
    ^chmod +x ($dir | path join sudo)
    let shells = [
        {name: zsh, argv: [zsh -f], script: {|fake| zsh-script $fake }}
        {name: nu, argv: [/usr/bin/nu --no-config-file], script: {|fake| nu-script $fake }}
    ]
    let cases = [
        [name markers tty ran];
        ["no terminal" [] false false]
        ["agent at a terminal" [CLAUDECODE] true false]
        ["other agent at a terminal" [GEMINI_CLI] true false]
        ["person at a terminal" [] true true]
    ]
    let failures = $shells | each {|shell|
        $cases | each {|c|
            let r = guard-run $dir $shell $c.markers $all --tty=$c.tty
            let out = $r.stdout + $r.stderr
            let name = $"($shell.name), ($c.name)"
            if $r.exit_code == $WRONG_SUDO_EXIT {
                $"($name): sudo did not resolve to the fake, not run"
            } else if ($out | str contains $RAN) != $c.ran {
                $"($name): sudo ran is ($out | str contains $RAN), wants ($c.ran): ($out | str trim)"
            } else if not $c.ran and not ($out | str contains $REFUSED) {
                $"($name): no refusal message: ($out | str trim)"
            }
        }
    } | flatten | compact | append (alias-order-check) | append (marker-parity-check $all)
    rm -rf $dir
    if ($failures | is-not-empty) {
        print --stderr ($failures | str join "\n")
        exit 1
    }
}
