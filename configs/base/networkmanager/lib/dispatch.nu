# The NM dispatchers' shared helpers, copied beside them to dispatcher.d/lib/ (NM runs no directory), so each one's
# `use lib/dispatch.nu` holds in the repo and under /etc alike. A missing binary reads as a failed command, not a crash
# that leaves a link undecided.

const LAB_ENV = "/etc/NetworkManager/homelab.env"

export def --wrapped out [...argv: string]: nothing -> string {
    try { do { run-external ...$argv } | complete | get stdout } catch { "" }
}

export def --wrapped ok [...argv: string]: nothing -> bool {
    try { (do { run-external ...$argv } | complete).exit_code == 0 } catch { false }
}

# Runs argv, passing its stderr on when it fails.
export def --wrapped attempt [...argv: string]: nothing -> nothing {
    let r = try { do { run-external ...$argv } | complete } catch {|e| {exit_code: 1, stderr: $"($e.msg)\n"} }
    if $r.exit_code != 0 { print --stderr --no-newline $r.stderr }
}

# A missing file has no lines.
export def file-lines [file: path]: nothing -> list<string> {
    if ($file | path exists) { open --raw $file | lines } else { [] }
}

# Whether a link has a device node: a nic, not a bridge, tunnel or veth.
export def link-physical [link: string]: nothing -> bool {
    $"/sys/class/net/($link)/device" | path exists
}

# `ip -4 route show default dev <link>`'s gateway.
export def route-gateway [route: string]: nothing -> any {
    $route | lines | get --optional 0 | default "" | parse --regex '^default via (?<gw>\S+)' | get --optional 0.gw
}

# homelab.env's KEY=value lines, quotes stripped; a missing file is {} (state.nu's env-file-load).
export def lab-env [file: path = $LAB_ENV]: nothing -> record {
    file-lines $file | parse --regex '^(?<key>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$'
    | reduce --fold {} {|e, acc| $acc | upsert $e.key ($e.value | str trim | str replace --regex '^"(.*)"$' '$1') }
}

export def lab-nets [lab: record]: nothing -> list<string> {
    $lab.HOMELAB_NETS? | default "" | split row " " | where $it != ""
}
