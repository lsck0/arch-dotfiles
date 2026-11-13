#!/usr/bin/env -S nu --no-config-file
# aliases.zsh's and aliases.nu's pacman run plain pacman for what only reads and sudo-at-terminal pacman for what
# changes the system, the same split in both shells. Each shell gets its rc's sudo-at-terminal and the wrapper, a fake
# sudo and pacman first on PATH, and a terminal with no agent marker, so the guard lets the call through to the fake.

const HERE = path self .
const ALIASES_ZSH = $HERE | path join aliases.zsh
const ALIASES_NU = $HERE | path join aliases.nu
const ZSHRC = $HERE | path join .. .. core zsh zshrc
const CONFIG_NU = $HERE | path join .. .. core nushell config.nu
const CLI_NU = $HERE | path join .. .. .. scripts lib cli.nu
const MARKERS_NU = "const AGENT_MARKERS"
const SUDO_PREFIX = "sudo "

const CASES = [
    [argv sudo];
    [[-Q] false]
    [[-Qi foo] false]
    [[--query --info foo] false]
    [[-T foo] false]
    [[--version] false]
    [[-h] false]
    [[-F ls] false]
    [[--files ls] false]
    [[-Fy] true]
    [[-Ss foo] false]
    [[-Si foo] false]
    [[--sync --search foo] false]
    [[-Sg] false]
    [[-Sl] false]
    [[-Sp foo] false]
    [[-S foo] true]
    [[--sync foo] true]
    [[-Sys foo] true]
    [[--sync --refresh --search foo] true]
    [[-Syu] true]
    [[-Sc] true]
    [[-Sw foo] true]
    [[-R foo] true]
    [[-U foo.pkg.tar.zst] true]
    [[-R -- -Q] true]
]

def line-starting [file: path, head: string]: nothing -> string {
    open --raw $file | lines | where ($it | str starts-with $head) | first
}

# The lines from the one starting with head through the next closing brace.
def block [file: path, head: string]: nothing -> list<string> {
    let lines = open --raw $file | lines
    let first = $lines | enumerate | where ($it.item | str starts-with $head) | get 0.index
    let last = $lines | enumerate | skip ($first + 1) | where ($it.item | str starts-with "}") | get 0.index
    $lines | slice $first..$last
}

def zsh-script []: nothing -> string {
    let guard = block $ZSHRC "sudo-at-terminal()"
    let calls = $CASES | each {|c| $"pacman ($c.argv | str join ' ')" }
    [(line-starting $ZSHRC "agent-session()") ...$guard (open --raw $ALIASES_ZSH) ...$calls] | str join "\n"
}

def nu-script []: nothing -> string {
    let guard = block $CONFIG_NU "def --wrapped sudo-at-terminal"
    let calls = $CASES | each {|c| $"pacman ($c.argv | str join ' ')" }
    [(line-starting $CONFIG_NU $MARKERS_NU) (line-starting $CONFIG_NU "let agent_session") ...$guard (open --raw $ALIASES_NU) ...$calls]
    | str join "\n"
}

def shell-run [dir: path, name: string, argv: list<string>, script: string, markers: list<string>]: nothing -> list<string> {
    let file = $dir | path join $"wrapper.($name)"
    $script | save --force $file
    let unset = $markers | each {|m| [-u $m] } | flatten
    let cmd = [env ...$unset $"PATH=($dir):/usr/bin" ...$argv $file] | str join " "
    ^script -qec $cmd /dev/null | complete | get stdout | lines | each { str trim } | where ($it | is-not-empty)
}

def main [] {
    let markers = line-starting $CLI_NU $MARKERS_NU | parse --regex '\[(?<names>[^\]]*)\]' | get 0.names | split row " "
    let dir = mktemp -d
    for fake in [sudo pacman] {
        $"#!/bin/sh\necho ($fake) \"$*\"\n" | save ($dir | path join $fake)
        ^chmod +x ($dir | path join $fake)
    }
    let shells = [
        {name: zsh, argv: [zsh -f], script: (zsh-script)}
        {name: nu, argv: [/usr/bin/nu --no-config-file], script: (nu-script)}
    ]
    let failures = $shells | each {|shell|
        let out = shell-run $dir $shell.name $shell.argv $shell.script $markers
        if ($out | length) != ($CASES | length) {
            return [$"($shell.name): ($out | length) lines for ($CASES | length) calls: ($out | str join ' | ')"]
        }
        $CASES | zip $out | each {|p|
            let args = $p.0.argv | str join " "
            let want = if $p.0.sudo { $"($SUDO_PREFIX)pacman ($args)" } else { $"pacman ($args)" }
            if $p.1 != $want { $"($shell.name), pacman ($args): ran '($p.1)', wants '($want)'" }
        } | compact
    } | flatten
    rm -rf $dir
    if ($failures | is-not-empty) {
        print --stderr ($failures | str join "\n")
        exit 1
    }
}
