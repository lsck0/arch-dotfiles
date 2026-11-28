#!/usr/bin/env -S nu --no-config-file
# dot's entry, which parses nothing but itself: nushell parses a whole script and all it uses before main runs, a
# third of a second for the whole CLI. plan, apply and status go straight to pipeline-cli.nu, which parses only the
# pipeline; every other command, and their --help, to the whole CLI in scripts/lib/dot-cli.nu. An apply takes run.lock
# here, before pipeline-cli.nu parses: re-execing under the flock there would pay that parse twice.

const LIB = path self | path expand | path dirname --num-levels 2 | path join scripts lib
const CLI = $LIB | path join dot-cli.nu
const PIPELINE_CLI = $LIB | path join pipeline-cli.nu
const PIPELINE_COMMANDS = [plan apply status]
const HELP_WORDS = [--help -h]
# the pipeline command that writes the user layer, under run.lock
const LOCKED_COMMAND = "apply"

use ($LIB | path join reexec.nu) [user-locked]

def --wrapped main [...args: string]: nothing -> nothing {
    let pipeline = ($args | get --optional 0) in $PIPELINE_COMMANDS and not ($args | any { $in in $HELP_WORDS })
    let argv = [$nu.current-exe --no-config-file (if $pipeline { $PIPELINE_CLI } else { $CLI }) ...$args]
    if $pipeline and $args.0 == $LOCKED_COMMAND { user-locked --argv $argv }
    exec ...$argv
}
