#!/usr/bin/nu --no-config-file
# pkexec target: the VM test's pasta and passt as the caller with group vmnet, whose DoT to quad9 alone skips
# portmaster (it blocks the guest's DoT as a secure-dns bypass). polkit runs it unprompted for an admin at the machine,
# so it takes only checked values and builds the command with the root copy's vm.nu, never a command of the caller's.

use /var/lib/dotfiles/repo/scripts/lib/vm.nu [vm-network-command]

const GROUP = "vmnet"
# the paths land unquoted in pasta's sh -c, so no shell metacharacters
const PATH_SAFE = '^/[A-Za-z0-9_./-]+$'
const ADDRESS = '^[0-9A-Fa-f.:]+$'
const CIDR = '^[0-9A-Fa-f.:]+/[0-9]{1,3}$'

def checked [value: string, pattern: string, what: string]: nothing -> string {
    if $value !~ $pattern { error make {msg: $"vm-net: bad ($what): ($value)"} }
    $value
}

def main [
    socket: string, pidfile: string, log: string, host_port: int, dns: string, forward: bool, ipv6: bool,
    ...block: string
]: nothing -> nothing {
    let uid = $env.PKEXEC_UID? | default ""
    if $uid !~ '^[0-9]+$' { error make {msg: "vm-net: run it through pkexec"} }
    if $host_port < 1024 or $host_port > 65535 { error make {msg: $"vm-net: bad port: ($host_port)"} }
    let net = {
        socket: (checked $socket $PATH_SAFE socket)
        pidfile: (checked $pidfile $PATH_SAFE pidfile)
        log: (checked $log $PATH_SAFE log)
        host_port: $host_port
        dns: (checked $dns $ADDRESS dns)
        forward: $forward
        ipv6: $ipv6
        block: ($block | each { checked $in $CIDR cidr })
    }
    let argv = vm-network-command $net
    # the log is opened after the drop, so it is the caller's file
    ^setsid -f setpriv $"--reuid=($uid)" $"--regid=($GROUP)" --init-groups -- sh -c 'exec "$@" > "$0" 2>&1' $net.log ...$argv
}
