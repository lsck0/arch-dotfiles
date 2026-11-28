#!/usr/bin/env -S nu --no-config-file
# Reloads the running herdr server's config; a server that is not running reads the new file when it starts.

def main []: nothing -> nothing {
    let r = do { ^herdr server reload-config } | complete
    # the result on stdout, an error on stderr
    let out = try { $r.stdout + $r.stderr | from json } catch { null }
    if ($out | get --optional error.code) == server_not_running { return }
    if $r.exit_code != 0 or ($out | get --optional result.status) != applied {
        print --stderr $"herdr-reload: ($r.stdout + $r.stderr | str trim)"
        exit 1
    }
    # applied all the same: what herdr said about the config is worth reading, not a failure
    let diagnostics = $out | get --optional result.diagnostics | default []
    if ($diagnostics | is-not-empty) { print --stderr $"herdr-reload: ($diagnostics | to json --raw)" }
}
