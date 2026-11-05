#!/usr/bin/env -S nu --no-config-file

const ROUTER = "@ROUTER@"
const ROUTER_TUNNEL = "@ROUTER_TUNNEL@"
const PC = "@HOST@"
const KNOCK = [@KNOCK@]
const PORT = "@PORT@"
const HOME_NETWORK = "/run/home-network"
const WG_IFACE = "wg0"
const PROBE_TIMEOUT_S = 2
const TRIES = 45
const TRY_INTERVAL = 2sec

# the interface the kernel would send to ADDRESS through
def route-dev [address: string]: nothing -> string {
    do { ^ip -o route get $address } | complete | get stdout | parse -r 'dev (?<dev>\S+)' | get --optional 0.dev
    | default ""
}

def at-home []: nothing -> bool {
    ($HOME_NETWORK | path exists) and (open --raw $HOME_NETWORK | lines | where $it != "" | is-not-empty)
}

# Home: the lan address. Away: only the tunnel reaches the router; its lan address is unrouted there, or a foreign
# lan on the same subnet (every fritzbox hands out 192.168.178.0/24) answers it instead.
def router-address []: nothing -> any {
    if (at-home) { return $ROUTER }
    let wg = $"/sys/class/net/($WG_IFACE)" | path exists
    if not $wg {
        print --stderr "wake-pc: away from home and wg0 is down; bring the home vpn up first (bar: network, Home VPN)"
        exit 1
    }
    if $ROUTER_TUNNEL != "" { return $ROUTER_TUNNEL }
    if (route-dev $ROUTER) == $WG_IFACE { return $ROUTER }
    print --stderr $"wake-pc: ($ROUTER) routes out (route-dev $ROUTER), not wg0, and no tunnel address is set \(base/ssh.wake_router_tunnel\)"
    exit 1
}

def main []: nothing -> nothing {
    let router = router-address
    # the tunnel address checks against the router's lan host key, in the homelab's known_hosts (base/ssh hosts block)
    let key = [-o $"HostKeyAlias=($ROUTER)" -o $"UserKnownHostsFile=($nu.home-dir)/.ssh/known_hosts.homelab"]
    try { ^ssh -o ConnectTimeout=5 ...$key $"root@($router)" wol-pc } catch {
        print --stderr $"wake-pc: the router at ($router) did not send the magic packet"
        exit 1
    }
    if not (at-home) and (route-dev $PC) != $WG_IFACE {
        print --stderr $"wake-pc: magic packet sent; ($PC) is shadowed by this network \(routes out (route-dev $PC)\), ssh in from the router"
        exit 1
    }
    print --stderr $"wake-pc: magic packet sent, waiting for ($PC) ..."
    # knock every try: it only opens the sshd port once the desktop's firewall is loaded
    for _ in 1..$TRIES {
        ^knock $PC ...($KNOCK | each { into string })
        if (do { ^nc -z -w $PROBE_TIMEOUT_S $PC $PORT } | complete).exit_code == 0 { exec sshk $PC }
        sleep $TRY_INTERVAL
    }
    print --stderr $"wake-pc: ($PC) did not answer ssh within ~3min"
    exit 1
}
