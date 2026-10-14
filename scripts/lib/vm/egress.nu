use prelude.nu *

const REPO = "/var/lib/dotfiles/repo"
const NFT_FILE = $REPO | path join configs/base/portmaster/portmaster-bypass.nft
const CONF = "/etc/wireguard/protonvpn-netns.conf"
const RUN = "/usr/local/lib/protonvpn-netns/run"
const NS = "protonvpn"
const BYPASS = "/tmp/egress.bypass"
# qemu's user-net host, the peer's endpoint
const QEMU_HOST = "10.0.2.2"
const BEACON_TIMEOUT_S = 5
const CURL_TIMEOUT_S = 8
const DNS_TIMEOUT_S = 30

def links []: nothing -> string {
    output { ^ip -n $NS -o link show } | lines | parse --regex '^\d+: (?<name>[^@:]+)' | get name | sort | str join ","
}

def refused [command: closure]: nothing -> string {
    let run = do $command | complete
    if ($run.stdout + $run.stderr | str contains $"namespace '($NS)' is down") { "refused" } else { "started" }
}

def beacon [tag: string]: nothing -> string { $"http://($HOST)/beacon/($tag)" }

# the host must see this one, or a leak beacon that never came proves nothing
^curl -s -m $BEACON_TIMEOUT_S (beacon drill-control) | ignore

^curl -so $BYPASS $"http://($HOST)/step/egress.bypass" | ignore
for phase in [away home] {
    do --ignore-errors { ^ip netns add drill-bypass }
    do --ignore-errors { ^ip netns exec drill-bypass nu --no-config-file $BYPASS $NFT_FILE $phase }
    do --ignore-errors { ^ip netns del drill-bypass }
}
say bypass_deployed (succeeds { ^cmp $NFT_FILE /etc/nftables.d/portmaster-bypass.nft } | yesno)
let live = [pentest libvirt-qemu] | all {|group|
    let gid = output { ^getent group $group } | split row ":" | get --optional 2
    $gid == null or (succeeds { ^nft get element inet portmaster_bypass gids $"{ ($gid) }" })
}
say bypass_live_gids ($live | yesno)

if ($CONF | path exists) {
    say vpn_conf preexisting
    report
    exit 0
}
say vpn_conf drill
let secrets = mktemp --directory --tmpdir-path /run drill-secrets.XXXXXX
$"[Interface]
PrivateKey = (^wg genkey | str trim)
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
PublicKey = (^wg genkey | ^wg pubkey | str trim)
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ($QEMU_HOST):9
" | save ($secrets | path join protonvpn-netns.conf)
let module = try {
    with-env {DOTFILES_SECRETS: $secrets} { ^nu --no-config-file ($REPO | path join scripts/lib/system-apply.nu) module base/protonvpn-netns system }
    "ok"
} catch { "failed" }
say vpn_module $module
rm --recursive --force $secrets

say vpn_links (links)
say vpn_routes (output { ^ip -n $NS route show } | lines | str trim --right | str join ",")
say vpn_ipv6_off (output { ^ip netns exec $NS sysctl -n net.ipv6.conf.all.disable_ipv6 })
say vpn_route_host (output { ^ip -n $NS route get $QEMU_HOST } | parse --regex 'dev (?<dev>\S+)' | get dev | str join "\n")
say vpn_run_user (output { ^$RUN id -un })
say vpn_run_ns (succeeds { ^$RUN ip -o link show wg-protonvpn } | yesno)
say vpn_up_curl (succeeds { ^$RUN curl -s -m $CURL_TIMEOUT_S (beacon drill-leak-up) } | yesno)
say vpn_up_dns (succeeds { ^timeout $DNS_TIMEOUT_S $RUN getent hosts archlinux.org } | yesno)

do --ignore-errors { ^ip -n $NS link set wg-protonvpn down }
say vpn_down_route (if (succeeds { ^ip -n $NS route get $QEMU_HOST }) { "yes" } else { "none" })
say vpn_down_curl (succeeds { ^$RUN curl -s -m $CURL_TIMEOUT_S (beacon drill-leak-down) } | yesno)

do --ignore-errors { ^ip -n $NS link del wg-protonvpn }
say vpn_gone_links (links)
say vpn_gone_leak (succeeds { ^ip netns exec $NS curl -s -m $BEACON_TIMEOUT_S (beacon drill-leak-gone) } | yesno)
say vpn_gone_run (refused { ^$RUN true })
say vpn_gone_shim (refused { ^sudo -u $env.SUDO_USER /usr/local/bin/yt-dlp --version })

do --ignore-errors { ^systemctl restart protonvpn-netns.service }
say vpn_restart_links (links)
do --ignore-errors { ^systemctl stop protonvpn-netns.service }
let ns_present = output { ^ip netns list } | lines | any { ($in | split row " " | first) == $NS }
say vpn_stopped_ns (if $ns_present { "present" } else { "absent" })
say vpn_stopped_run (refused { ^$RUN true })

do --ignore-errors { ^systemctl disable protonvpn-netns.service }
rm --force $CONF
report
