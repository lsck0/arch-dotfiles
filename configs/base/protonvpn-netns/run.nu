#!/usr/bin/nu --no-config-file
# run <command> [args...]: run any command inside the protonvpn namespace as the user who called sudo. root is used only
# for the namespace switch; setpriv then drops to that user with no privileges before the command runs, so the command
# never runs as root and only its traffic egresses through the proton tunnel. the shims (shim.nu) and the `vpn` wrapper
# both reach it; every command still runs as the unprivileged caller

const NS = "protonvpn"
const IFACE = "wg-protonvpn"
# only names, never paths or options, from the caller's environment (sudoers env_keep)
const PASSED = [WAYLAND_DISPLAY DISPLAY TERM COLORTERM LANG]
const PLAIN = '^[A-Za-z0-9_.:@-]*$'
const SETPRIV = [--init-groups --inh-caps=-all --bounding-set=-all]

def fail [message: string, code: int]: nothing -> nothing {
    print --stderr $"protonvpn-netns: ($message)"
    exit $code
}

def --wrapped main [...command: string]: nothing -> nothing {
    let user = $env.SUDO_USER? | default ""
    if $user == "" { fail "run through sudo" 1 }
    if ($command | is-empty) { fail "usage: run <command> [args...]" 2 }
    let uid = ^id -u $user | str trim
    let gid = ^id -g $user | str trim
    # fail closed: no namespace or tunnel, no start; the command never falls back onto the real link
    if (do { ^ip -n $NS link show $IFACE } | complete).exit_code != 0 {
        fail $"namespace '($NS)' is down \(systemctl status protonvpn-netns\), not starting ($command.0)" 1
    }
    let home = ^getent passwd $user | str trim | split row ":" | get 5
    let passed = $PASSED | each {|name|
        let value = $env | get --optional $name | default ""
        $"($name)=(if $value =~ $PLAIN { $value } else { '' })"
    }
    let env_vars = [
        $"HOME=($home)" $"USER=($user)" $"LOGNAME=($user)" "PATH=/usr/local/bin:/usr/bin"
        $"XDG_RUNTIME_DIR=/run/user/($uid)" $"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/($uid)/bus"
    ] ++ $passed
    exec ip netns exec $NS setpriv $"--reuid=($uid)" $"--regid=($gid)" ...$SETPRIV env -i ...$env_vars ...$command
}
