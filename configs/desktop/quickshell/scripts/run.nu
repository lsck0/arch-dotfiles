#!/usr/bin/env -S nu --no-config-file
# The launcher's > run: one shell command in its app scope, a notification with its last error line when it fails.

const HERE = path self | path expand | path dirname
use ($HERE | path join lib shell.nu) [action-notify]

const RUN_GLYPH = "\u{f018d}"

# --wrapped with untyped words: a lone true, null or --help is a command, not a nu value or flag
def --wrapped main [...words]: nothing -> nothing {
    let command = $words | each { into string } | str join " "
    # stderr to a file rather than a pipe, so a long-running GUI command holds no growing buffer; stdout stays the scope's
    let err_path = mktemp -t launcher-run.XXXXXX
    let code = try { ^sh -c -- $command e> $err_path; 0 } catch { $env.LAST_EXIT_CODE }
    let reason = open --raw $err_path | lines | where $it != "" | last 1 | get --optional 0 | default $"exited ($code)"
    rm -f $err_path
    if $code != 0 { action-notify $RUN_GLYPH "Command failed" $"($reason)\n> ($command)" }
}
