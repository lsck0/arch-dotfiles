# Waking the desktop through the homelab router's wol-pc (base/ssh.wake_router) and waiting for its sshd behind the
# knock: wake-pc's whole job and offload's connect. All over ipv4: fw-inbound's knock sets hold ipv4 addresses only.
use ../../../../scripts/lib/state.nu [file-lines]
use ../../../../scripts/lib/usage.nu [die]

const HOME_NETWORK = "/run/home-network"
const WG_IFACE = "wg0"
const PROBE_TIMEOUT_S = 2
const ROUTER_TIMEOUT_S = 5
const WAKE_TRIES = 45
const WAKE_INTERVAL = 2sec

# Why the host is out of reach from here, or null when home or the tunnel routes its lan address.
export def reach-blocker [at_home: bool, wg_up: bool, route_dev: string]: nothing -> any {
    if $at_home { return null }
    if not $wg_up { return $"away from home and ($WG_IFACE) is down; bring the home vpn up first \(bar: network, Home VPN\)" }
    if $route_dev != $WG_IFACE {
        $"the host's address routes out ($route_dev), not ($WG_IFACE): this network shadows the home lan"
    }
}

# The router address that sends the wake packet: the lan one at home, the tunnel one away, null when none fits.
# Away, the lan address is unrouted, or a foreign lan on the same subnet (every fritzbox hands out 192.168.178.0/24)
# answers it instead.
export def router-address [config: record, at_home: bool, route_dev: string]: nothing -> any {
    if $config.router == null { return null }
    if $at_home { return $config.router }
    if $config.router_tunnel != null { return $config.router_tunnel }
    if $route_dev == $WG_IFACE { $config.router }
}

def at-home []: nothing -> bool { file-lines $HOME_NETWORK | is-not-empty }

def wg-up []: nothing -> bool { $"/sys/class/net/($WG_IFACE)" | path exists }

# The interface the kernel would send to address through.
def route-dev [address: string]: nothing -> string {
    do { ^ip -o route get $address } | complete | get stdout | parse --regex 'dev (?<dev>\S+)' | get --optional 0.dev
    | default ""
}

# Where this machine sits (home, the tunnel, away) and why host is out of reach from here, null when it is not.
export def host-reach [host: string]: nothing -> record<network: string, blocker: any> {
    let home = at-home
    let wg = wg-up
    {
        network: (if $home { "home" } else if $wg { $WG_IFACE } else { "away" })
        blocker: (reach-blocker $home $wg (route-dev $host))
    }
}

export def port-open [host: string, port: int]: nothing -> bool {
    (do { ^nc -4 -z -w $PROBE_TIMEOUT_S $host ($port | into string) } | complete).exit_code == 0
}

# Knocks (base/nftables), then probes the hidden sshd port; the knock only opens it once the host's firewall is up.
export def knock-open [config: record, tries: int]: nothing -> bool {
    for _ in 1..$tries {
        ^knock -4 $config.host ...($config.knock | each { into string })
        if (port-open $config.host $config.port) { return true }
    }
    false
}

# Sends the wake packet through the router and waits until the knock opens config.host's sshd; dies when nothing can
# wake it or it stays silent. config: host, port, knock, router, router_tunnel, unlock_port (base/boot/remote-unlock's
# initramfs sshd, null for none). A host woken from power-off stops at its LUKS prompt there: --unlock-interactive
# asks for the passphrase once and waits on, otherwise it dies naming the command.
export def host-wake [config: record, --unlock-interactive]: nothing -> nothing {
    let home = at-home
    let wg = wg-up
    if not $home and not $wg { die (reach-blocker $home $wg "") }
    let router_dev = if $config.router != null { route-dev $config.router } else { "" }
    let router = router-address $config $home $router_dev
    if $config.router == null { die $"($config.host) does not answer and no router is set to wake it \(base/ssh.wake_router\)" }
    if $router == null {
        die $"($config.router) routes out ($router_dev), not ($WG_IFACE), and no tunnel address is set \(base/ssh.wake_router_tunnel\)"
    }
    # the tunnel address checks against the router's lan host key, in the homelab's known_hosts (base/ssh hosts block)
    let key = [-o $"HostKeyAlias=($config.router)" -o $"UserKnownHostsFile=($nu.home-dir)/.ssh/known_hosts.homelab"]
    let sent = do { ^ssh -o $"ConnectTimeout=($ROUTER_TIMEOUT_S)" ...$key $"root@($router)" wol-pc } | complete
    if $sent.exit_code != 0 { die $"the router at ($router) did not send the magic packet: ($sent.stderr | str trim)" }
    # the packet still wakes a host this network shadows: only the ssh after it has to go through the router
    let blocker = reach-blocker $home $wg (route-dev $config.host)
    if $blocker != null { die $"magic packet sent, but ($blocker); ssh in from the router" }
    print --stderr $"magic packet sent, waiting for ($config.host) ..."
    mut unlocked = false
    for _ in 1..$WAKE_TRIES {
        if (knock-open $config 1) { return }
        let unlock = $config.unlock_port?
        if not $unlocked and $unlock != null and (port-open $config.host $unlock) {
            if not $unlock_interactive {
                die $"($config.host) waits for its disk passphrase: ssh -4 -p ($unlock) root@($config.host), then run this again"
            }
            # tinysshd stays up until the boot leaves the initramfs: ask once, then wait for the real sshd
            try { ^ssh -4 -p $unlock $"root@($config.host)" }
            $unlocked = true
        }
        sleep $WAKE_INTERVAL
    }
    die $"($config.host) did not answer ssh or the unlock prompt within ~($WAKE_TRIES * $WAKE_INTERVAL)"
}
