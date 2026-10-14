#!/usr/bin/nu --no-config-file
# the root half of scripts/toggles, run through pkexec: a fixed set of verbs, every argument checked here, so the polkit
# rule that lets the bar call it unprompted hands out exactly these and nothing else

const PERSONA_LOCKDOWN = "/run/persona-lockdown"
const WG_INTERFACE = "wg0"
const WG_CONFIG = "/etc/wireguard/wg0.conf"
const PERSONA_DISPATCHER = "/etc/NetworkManager/dispatcher.d/90-anonymous-persona"
const NFT_TABLE = "anonymous_socks"
const PERSONA_CHAIN = "ANONSOCKS_PERSONA"
const TLP_MODES = [balanced performance power-saver]
const PERSONA_TTLS = ["64" "128"]
const PORT_MAX = 65535
const POOL_SIZE_MAX = 999

def usage []: nothing -> nothing {
    print -e "usage: toggle-root {tlp MODE|wg up|down|vllm on|off|firewall-chosen|anonsocks VERB...}"
    exit 1
}

# the caller's uid from pkexec; run directly as root there is no caller to scope to
def caller-uid []: nothing -> string {
    let uid = $env.PKEXEC_UID? | default ""
    if $uid !~ '^[0-9]+$' {
        print -e "toggle-root: no PKEXEC_UID, run it through pkexec"
        exit 1
    }
    $uid
}

def persona-off []: nothing -> nothing {
    for ipt in [iptables ip6tables] {
        # the cgroup is gone once tor stops, so the jump is found by chain name rather than by its match; -S quotes the
        # --path, whose checked charset holds no space
        let jumps = ^$ipt -t mangle -S POSTROUTING | complete | get stdout | lines | where ($it | str contains $"-j ($PERSONA_CHAIN)")
        for rule in $jumps {
            let rule_args = $rule | str replace "-A" "-D" | split row " " | str trim --char '"'
            try { ^$ipt -t mangle ...$rule_args } catch { print -e $"toggle-root: ($ipt) could not delete: ($rule)" }
        }
        ^$ipt -t mangle -F $PERSONA_CHAIN | complete
        ^$ipt -t mangle -X $PERSONA_CHAIN | complete
    }
}

def anonsocks [args: list<string>]: nothing -> nothing {
    match [($args | length) ($args.0? | default "")] {
        # <base port> <pool size> <new connections/sec>
        [4, "rate-on"] => {
            if ($args | skip 1 | any { $in !~ '^[0-9]{1,6}$' }) { usage }
            let port = $args.1 | into int
            let pool = $args.2 | into int
            let rate = $args.3 | into int
            let last = $port + $pool - 1
            if not ($port >= 1 and $pool in 1..$POOL_SIZE_MAX and $last <= $PORT_MAX and $rate >= 1) { usage }
            $"table inet ($NFT_TABLE) {
    chain out {
        type filter hook output priority 0; policy accept;
        oif \"lo\" tcp dport ($port)-($last) ct state new limit rate over ($rate)/second drop
    }
}
" | ^nft -f -
        }
        [1, "egress-on"] => {
            # the caller's own anonsocks.slice, never a path it names
            let uid = caller-uid
            let slice = $"user.slice/user-($uid).slice/user@($uid).service/anonsocks.slice"
            $"table inet ($NFT_TABLE) {
    chain egress {
        type filter hook output priority 0; policy accept;
        socket cgroupv2 level 4 \"($slice)\" oif != \"lo\" reject
        # redirected to lo, e.g. portmaster's dns, the lookup still leaves in the clear
        socket cgroupv2 level 4 \"($slice)\" ct status dnat reject
    }
}
" | ^nft -f -
        }
        [1, "nft-off"] => { ^nft delete table inet $NFT_TABLE | complete | ignore }
        # <ttl> <tor unit cgroup>; the cgroup has to sit inside the caller's own user manager
        [3, "persona-on"] => {
            let ttl = $args.1
            let cgroup = $args.2
            let uid = caller-uid
            let cgroup_pattern = $'^user\.slice/user-($uid)\.slice/user@($uid)\.service/[A-Za-z0-9@._/-]+$'
            if $ttl not-in $PERSONA_TTLS or $cgroup !~ $cgroup_pattern or ($cgroup | str contains "..") { usage }
            persona-off
            for ipt in [iptables ip6tables] {
                if (^$ipt -t mangle -N $PERSONA_CHAIN | complete).exit_code != 0 { ^$ipt -t mangle -F $PERSONA_CHAIN }
                let hop_limit = if $ipt == iptables { [TTL --ttl-set] } else { [HL --hl-set] }
                ^$ipt -t mangle -A $PERSONA_CHAIN -j ...$hop_limit $ttl
                try {
                    ^$ipt -t mangle -A POSTROUTING -m cgroup --path $cgroup -j $PERSONA_CHAIN
                } catch {
                    print -e $"toggle-root: ($ipt) persona jump failed, tor runs without it"
                }
            }
        }
        [1, "persona-off"] => { persona-off }
        _ => { usage }
    }
}

def --wrapped main [...args: string] {
    match [($args | length) ($args.0? | default "")] {
        [2, "tlp"] => {
            let mode = $args.1
            if $mode in $TLP_MODES {
                ^tlp $mode
            } else if $mode == start {
                # un-force: back to tlp's own ac/bat auto-detect
                ^tlp start o> /dev/null
            } else {
                usage
            }
        }
        [2, "wg"] => {
            if not ($WG_CONFIG | path exists) {
                print -e $"toggle-root: no ($WG_INTERFACE) configured"
                exit 1
            }
            let direction = $args.1
            if $direction not-in [up down] { usage }
            ^wg-quick $direction $WG_INTERFACE
            # the persona's tor hands over to the full tunnel and back; NM may not dispatch a link wg-quick made
            if ($PERSONA_DISPATCHER | path exists) { try { ^$PERSONA_DISPATCHER $WG_INTERFACE $direction } }
        }
        # enable, not just start: on means the socket listens across reboots too
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
        # a state picked in the toggle is the user's, the persona dispatcher lifts only a lockdown that still has the marker
        [1, "firewall-chosen"] => { rm --force $PERSONA_LOCKDOWN }
        [_, "anonsocks"] => { anonsocks ($args | skip 1) }
        _ => { usage }
    }
}
