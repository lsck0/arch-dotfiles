#!/usr/bin/nu --no-config-file
# root half of scripts/toggles via pkexec: 49-toggles.rules grants only the verbs listed there, and this checks every
# argument again. main takes no flag and is not --wrapped: nu evaluates a --flag=(expr) argument of a script before
# main runs wherever the signature accepts that flag, here as root (toggle-root.test.nu)

const PERSONA_LOCKDOWN = "/run/persona-lockdown"
const WG_INTERFACE = "wg0"
const WG_CONFIG = "/etc/wireguard/wg0.conf"
const PERSONA_DISPATCHER = "/etc/NetworkManager/dispatcher.d/90-anonymous-persona"
const TRUSTED_NETWORK = "/run/trusted-network"
const PORTAL_UNIT = "persona-portal"
# one table for every login, a chain per caller uid in it: one login's verbs never flush or drop another's guard
const NFT_TABLE = "anonymous_socks"
# the caller's uid follows: with ten digits, iptables' longest chain name (28)
const PERSONA_CHAIN = "ANONSOCKS_PERSONA_"
const TLP_MODES = [balanced performance power-saver]
const FIREWALL_STATES = [permissive default restrictive]
const PERSONA_TTLS = ["64" "128"]
const PORT_MAX = 65535
const NFT_LISTING_FRAME = '^(table .*\{|chain .*\{|type .*|\}|)$'
const POOL_SIZE_MAX = 999
const GUARD_STOP_UNITS = [portmaster.service tor-router.service]
const TOR_UNIT = "tor-router.service"
# the persona dispatcher's mark on a tor it started: its tor-off stops a marked tor, so a user's choice drops the mark
const DISPATCHER_TOR = "/run/persona-tor"
const CGROUP_ROOT = "/sys/fs/cgroup"
const APPROVAL_DIR = "@APPROVAL_DIR@"
const APPROVAL_MINUTES = "@APPROVAL_MINUTES@"
# ps reports the process age in whole seconds
const APPROVAL_MARGIN = 5sec

def usage []: nothing -> nothing {
    print -e ("usage: toggle-root {tlp MODE|start|wg up|down|vllm on|off|ollama on|off|firewall STATE|raise-default|"
        + "portmaster-restore|portal on|off|tor-start|guard-stop UNIT...|anonsocks VERB...}")
    exit 1
}

def caller-uid []: nothing -> string {
    let uid = $env.PKEXEC_UID? | default ""
    if $uid !~ '^[0-9]+$' {
        print -e "toggle-root: no PKEXEC_UID, run it through pkexec"
        exit 1
    }
    $uid
}

# The stamp 49-toggles.rules reads: while it is younger than the window, a lowering verb passes unasked. Written only
# when it had run out before this process (pkexec, then this script) started, so only a call that was authenticated
# starts a window, and one the stamp let through never extends it.
def approval-record []: nothing -> nothing {
    let uid = $env.PKEXEC_UID? | default ""
    if $uid !~ '^[0-9]+$' { return }
    let stamp = $APPROVAL_DIR | path join (^id -un $uid | str trim)
    let started = (date now) - ((^ps -o etimes= -p $nu.pid | str trim | into int) * 1sec)
    let window = ($APPROVAL_MINUTES | into int) * 1min
    if ($stamp | path exists) and (ls --directory $stamp | get 0.modified) + $window + $APPROVAL_MARGIN >= $started {
        return
    }
    ^install -d -m 755 $APPROVAL_DIR
    ^install -m 644 /dev/null $stamp
}

def anonsocks-slice []: nothing -> string {
    let uid = caller-uid
    $"user.slice/user-($uid).slice/user@($uid).service/anonsocks.slice"
}

# The guard of a slice that still runs something stays: a process confined there must not drop or weaken its own.
# cgroup.events counts the slice's unit cgroups too, its own cgroup.procs is always empty.
def anonsocks-guard-release [what: string]: nothing -> nothing {
    let events = [$CGROUP_ROOT (anonsocks-slice) cgroup.events] | path join
    if ($events | path exists) and "populated 0" not-in (open --raw $events | lines) {
        print -e $"toggle-root: anonsocks.slice still runs something, ($what)"
        exit 1
    }
}

def persona-chain []: nothing -> string { $"($PERSONA_CHAIN)(caller-uid)" }

def persona-off []: nothing -> nothing {
    let chain = persona-chain
    for ipt in [iptables ip6tables] {
        # the cgroup is gone once tor stops, so the jump is found by its chain, the target that ends the rule
        let jumps = ^$ipt -t mangle -S POSTROUTING | complete | get stdout | lines | where ($it | str ends-with $" -j ($chain)")
        for rule in $jumps {
            let rule_args = $rule | str replace "-A" "-D" | split row " " | str trim --char '"'
            try { ^$ipt -t mangle ...$rule_args } catch { print -e $"toggle-root: ($ipt) could not delete: ($rule)" }
        }
        ^$ipt -t mangle -F $chain | complete
        ^$ipt -t mangle -X $chain | complete
    }
}

# Takes no link from the caller: the dispatcher's own idea of foreign, the connected physical links not trusted.
def portal [direction: string]: nothing -> nothing {
    if not ($PERSONA_DISPATCHER | path exists) {
        print -e "toggle-root: no persona dispatcher"
        exit 1
    }
    match $direction {
        on => {
            let trusted = if ($TRUSTED_NETWORK | path exists) { open --raw $TRUSTED_NETWORK | lines } else { [] }
            let links = ^nmcli -t -f DEVICE,STATE device | lines | parse --regex '^(?<dev>[^:]*):(?<state>.*)$'
                | where {|l| $l.state == connected and $l.dev not-in $trusted }
                | where {|l| $"/sys/class/net/($l.dev)/device" | path exists }
            if ($links | is-empty) {
                print -e "toggle-root: no foreign link to open a portal on"
                exit 1
            }
            for link in $links { ^$PERSONA_DISPATCHER $link.dev portal }
        }
        # the timer's service is the dispatcher's own portal-end, with the link's search domains it saved
        off => {
            let timers = ^systemctl list-units --type timer --state active --plain --no-legend $"($PORTAL_UNIT)-*.timer"
                | lines | parse --regex '^(?<unit>\S+)\.timer' | get unit
            for unit in $timers {
                ^systemctl start $"($unit).service"
                ^systemctl stop $"($unit).timer"
            }
        }
        _ => { usage }
    }
}

# The caller's own chain of the table: egress (the slice's guard) or out (the rate cap).
def anonsocks-chain [kind: string]: nothing -> string { $"($kind)_(caller-uid)" }

# Whether a listing of an `out` chain holds the cap for these numbers and no other rule; nft prints a range of one
# port as the port and adds its default burst.
export def anonsocks-rate-cap-loaded [listing: string, port: int, last: int, rate: int]: nothing -> bool {
    let rules = $listing | lines | str trim | where { $in !~ $NFT_LISTING_FRAME } | str replace --regex ' burst \d+ packets' ""
    let dport = if $last == $port { $port } else { $"($port)-($last)" }
    $rules == [$"oif \"lo\" tcp dport ($dport) ct state new limit rate over ($rate)/second drop"]
}

def anonsocks [args: list<string>]: nothing -> nothing {
    match [($args | length) ($args.0? | default "")] {
        [4, "rate-on"] => {
            if ($args | skip 1 | any { $in !~ '^[0-9]{1,6}$' }) { usage }
            let port = $args.1 | into int
            let pool = $args.2 | into int
            let rate = $args.3 | into int
            let last = $port + $pool - 1
            if not ($port >= 1 and $pool in 1..$POOL_SIZE_MAX and $last <= $PORT_MAX and $rate >= 1) { usage }
            # the numbers are the caller's, so they set a cap but never replace one over a running slice
            let chain = anonsocks-chain out
            let loaded = ^nft list chain inet $NFT_TABLE $chain | complete
            if $loaded.exit_code == 0 {
                # the same cap again is no change: a refusal here makes anonymous-socks-up tear the slice down
                if (anonsocks-rate-cap-loaded $loaded.stdout $port $last $rate) { return }
                anonsocks-guard-release "its rate cap stays as it is"
            }
            $"add table inet ($NFT_TABLE)
add chain inet ($NFT_TABLE) ($chain) { type filter hook output priority 0 ; policy accept ; }
flush chain inet ($NFT_TABLE) ($chain)
table inet ($NFT_TABLE) {
    chain ($chain) {
        type filter hook output priority 0; policy accept;
        oif \"lo\" tcp dport ($port)-($last) ct state new limit rate over ($rate)/second drop
    }
}
" | ^nft -f -
        }
        [1, "egress-on"] => {
            let slice = anonsocks-slice
            let chain = anonsocks-chain egress
            $"add table inet ($NFT_TABLE)
add chain inet ($NFT_TABLE) ($chain) { type filter hook output priority 0 ; policy accept ; }
flush chain inet ($NFT_TABLE) ($chain)
table inet ($NFT_TABLE) {
    chain ($chain) {
        type filter hook output priority 0; policy accept;
        socket cgroupv2 level 4 \"($slice)\" oif != \"lo\" reject
        # redirected to lo, e.g. portmaster's dns, the lookup still leaves in the clear
        socket cgroupv2 level 4 \"($slice)\" ct status dnat reject
    }
}
" | ^nft -f -
        }
        [1, "nft-off"] => {
            anonsocks-guard-release "its netfilter guard stays"
            for kind in [egress out] { ^nft delete chain inet $NFT_TABLE (anonsocks-chain $kind) | complete | ignore }
            # the table goes with the last login's chains
            let left = ^nft list table inet $NFT_TABLE | complete
            if $left.exit_code == 0 and not ($left.stdout | lines | any { $in =~ '^\s*chain ' }) {
                ^nft delete table inet $NFT_TABLE | complete | ignore
            }
        }
        [3, "persona-on"] => {
            let ttl = $args.1
            let cgroup = $args.2
            let uid = caller-uid
            let cgroup_pattern = $'^user\.slice/user-($uid)\.slice/user@($uid)\.service/[A-Za-z0-9@._/-]+$'
            if $ttl not-in $PERSONA_TTLS or $cgroup !~ $cgroup_pattern or ($cgroup | str contains "..") { usage }
            persona-off
            let chain = persona-chain
            for ipt in [iptables ip6tables] {
                if (^$ipt -t mangle -N $chain | complete).exit_code != 0 { ^$ipt -t mangle -F $chain }
                let hop_limit = if $ipt == iptables { [TTL --ttl-set] } else { [HL --hl-set] }
                ^$ipt -t mangle -A $chain -j ...$hop_limit $ttl
                try {
                    ^$ipt -t mangle -A POSTROUTING -m cgroup --path $cgroup -j $chain
                } catch {
                    print -e $"toggle-root: ($ipt) persona jump failed, tor runs without it"
                }
            }
        }
        [1, "persona-off"] => { persona-off }
        _ => { usage }
    }
}

# The dispatcher's own decision, as on every link event: on behind a raised firewall, but not over a proton tunnel,
# beside the netns tunnel where its mark is read, or on a foreign link with no tor to route into.
def portmaster-decide []: nothing -> nothing {
    if ($PERSONA_DISPATCHER | path exists) {
        ^$PERSONA_DISPATCHER "" portmaster
    } else {
        print -e "toggle-root: no persona dispatcher, portmaster left as it is"
    }
}

def firewall-raise [state: string]: nothing -> nothing {
    ^systemctl start (if $state == default { "fw-inbound.service" } else { "fw-lockdown.service" })
    portmaster-decide
}

def main [...args: string] {
    match [($args | length) ($args.0? | default "")] {
        [2, "tlp"] => {
            let mode = $args.1
            if (which tlp | is-empty) {
                print -e "toggle-root: tlp is not installed"
                exit 1
            }
            if $mode in $TLP_MODES {
                ^tlp $mode
            } else if $mode == start {
                ^tlp start o> /dev/null
            } else {
                usage
            }
        }
        [2, "wg"] => {
            if not ($WG_CONFIG | path exists) or (which wg-quick | is-empty) {
                print -e $"toggle-root: no ($WG_INTERFACE) configured"
                exit 1
            }
            let direction = $args.1
            if $direction not-in [up down] { usage }
            ^wg-quick $direction $WG_INTERFACE
            # NetworkManager may not dispatch a link wg-quick made
            if ($PERSONA_DISPATCHER | path exists) { try { ^$PERSONA_DISPATCHER $WG_INTERFACE $direction } }
        }
        [2, "vllm"] => {
            match $args.1 {
                on => { ^systemctl enable --now vllm.socket }
                off => {
                    ^systemctl disable --now vllm.socket
                    ^systemctl stop vllm-proxy.service vllm.service
                }
                _ => { usage }
            }
        }
        # socket-activated like vllm: off has to take the socket too, or the next request starts it again
        [2, "ollama"] => {
            match $args.1 {
                on => { ^systemctl enable --now ollama.socket }
                off => {
                    ^systemctl disable --now ollama.socket
                    ^systemctl stop ollama.service
                }
                _ => { usage }
            }
        }
        # permissive to default only tightens, so the rule never asks for it: from restrictive it would lower
        [2, "firewall"] if $args.1 == raise-default => {
            if (^systemctl is-active --quiet fw-lockdown.service | complete).exit_code == 0 {
                print -e "toggle-root: restrictive is active, default would lower it"
                exit 1
            }
            firewall-raise default
        }
        # one call per switch, so 49-toggles.rules asks once; portmaster stays off under a live protonvpn tunnel
        [2, "firewall"] => {
            let state = $args.1
            if $state not-in $FIREWALL_STATES { usage }
            if $state == permissive {
                ^systemctl stop fw-inbound.service fw-lockdown.service portmaster.service
            } else {
                firewall-raise $state
            }
            # the admin chose, so the dispatcher's lockdown marker no longer holds the link
            rm --force $PERSONA_LOCKDOWN
            if $state != restrictive { approval-record }
        }
        [1, "portmaster-restore"] => { portmaster-decide }
        [2, "portal"] => {
            portal $args.1
            if $args.1 == on { approval-record }
        }
        # what a route change lowers, in one call
        [_, "guard-stop"] => {
            let units = $args | skip 1
            if ($units | is-empty) or ($units | any { $in not-in $GUARD_STOP_UNITS }) { usage }
            ^systemctl stop ...$units
            if $TOR_UNIT in $units { rm --force $DISPATCHER_TOR }
            approval-record
        }
        # the user's tor: unmarked, so the dispatcher's tor-off on a trusted link leaves it running
        [1, "tor-start"] => {
            rm --force $DISPATCHER_TOR
            ^systemctl start $TOR_UNIT
        }
        [_, "anonsocks"] => { anonsocks ($args | skip 1) }
        _ => { usage }
    }
}
