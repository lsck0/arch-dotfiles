# The NM dispatchers' shared helpers, copied beside them to dispatcher.d/lib/ (NM runs no directory), so each one's
# `use lib/dispatch.nu` holds in the repo and under /etc alike; state.nu comes from the root copy, which each
# dispatcher's shebang puts on the lib path. gaming/vpn-bypass's games-route reaches this file through that lib path.
# A missing binary reads as a failed command, not a crash that leaves a link undecided.

export use state.nu [file-lines]
use state.nu [env-file-load]

const LAB_ENV = "/etc/NetworkManager/homelab.env"
const POLICY_FILE = "/etc/NetworkManager/untrusted-policy"

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

# base/networkmanager's untrusted_policy, "" when it was never written.
export def untrusted-policy []: nothing -> string {
    file-lines $POLICY_FILE | get --optional 0 | default "" | str trim
}

# Whether a link has a device node: a nic, not a bridge, tunnel or veth.
export def link-physical [link: string]: nothing -> bool {
    $"/sys/class/net/($link)/device" | path exists
}

# `ip -4 route show default dev <link>`'s gateway.
export def route-gateway [route: string]: nothing -> any {
    $route | lines | get --optional 0 | default "" | parse --regex '^default via (?<gw>\S+)' | get --optional 0.gw
}

export def lab-env []: nothing -> record { env-file-load $LAB_ENV }

export def lab-nets [lab: record]: nothing -> list<string> {
    $lab.HOMELAB_NETS? | default "" | split row " " | where $it != ""
}
