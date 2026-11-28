#!/usr/bin/env -S nu --no-config-file
# dot.nu hands plan, apply and status straight to pipeline-cli.nu and their --help to dot-cli.nu: both scripts take the
# same words, so the misuse pipeline-cli.nu turns away is what dot-cli.nu's signature would, and the help names dot.
use std/assert

const DOT = path self ../dot.nu
const CLI = path self dot-cli.nu
const PIPELINE_CLI = path self pipeline-cli.nu
const COMMANDS = [plan apply status]

def script-run [script: path, words: list<string>]: nothing -> record {
    with-env {DOT_SYSTEM: skip} { ^$nu.current-exe --no-config-file $script ...$words | complete }
}

# A help's usage line after the command's name and its flag names, the descriptions left out.
def help-shape [help: string]: nothing -> record {
    let lines = $help | lines
    {
        usage: ($lines | where $it =~ '^\s+> ' | first | str replace --regex '^\s+> \S+' '' | str trim)
        flags: ($lines | parse --regex '^\s+(?:-\w, )?(?<flag>--[a-z][a-z0-9-]*)' | get flag)
    }
}

def main []: nothing -> nothing {
    for command in $COMMANDS {
        let full = script-run $CLI [$command --help]
        let pipeline = script-run $PIPELINE_CLI [$command --help]
        assert equal (help-shape $pipeline.stdout) (help-shape $full.stdout) $"($command): pipeline-cli.nu takes what dot-cli.nu does"
        let shown = script-run $DOT [$command --help]
        assert equal $shown.exit_code 0 $"dot ($command) --help"
        assert str contains $shown.stdout $"> dot ($command) " $"dot ($command) --help names dot"
        let bogus = script-run $DOT [$command --bogus]
        assert equal $bogus.exit_code 2 $"dot ($command) --bogus is misuse"
        assert str contains $bogus.stderr $"dot: error: dot ($command) has no flag --bogus" $"dot ($command) --bogus in dot's form"
    }
    let unknown = script-run $DOT [apply no-such/module]
    assert equal $unknown.exit_code 2 "dot apply of an unknown module is misuse"
    assert str contains $unknown.stderr "dot: error: no module no-such/module" "dot apply of an unknown module names it"
    let contradiction = script-run $DOT [apply --system core/btop]
    assert equal $contradiction.exit_code 2 "dot apply --system with a module is misuse"
}
