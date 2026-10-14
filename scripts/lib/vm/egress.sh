# shellcheck shell=bash disable=SC2154  # host and step come from prelude.sh, run ahead of it
# runs on the test vm's guest as root, fetched by dot test (scripts/lib/vm.nu); @KEY@ placeholders are filled in there
repo=/var/lib/dotfiles/repo
nft_file=$repo/configs/base/portmaster/portmaster-bypass.nft
conf=/etc/wireguard/protonvpn-netns.conf
run=/usr/local/lib/protonvpn-netns/run
ns=protonvpn
links() { ip -n "$ns" -o link show | awk -F': ' '{ sub(/@.*/, "", $2); print $2 }' | sort | paste -sd,; }
refused() { if "$@" 2>&1 | grep -q "namespace '$ns' is down"; then echo refused; else echo started; fi; }
# the host must see this one, or a leak beacon that never came proves nothing
curl -s -m 5 "http://$host/beacon/drill-control" > /dev/null

fetch bypass
for phase in away home; do
    ip netns add drill-bypass
    ip netns exec drill-bypass bash "/tmp/$step.bypass" "$nft_file" "$phase"
    ip netns del drill-bypass
done
say bypass_deployed "$(yesno cmp "$nft_file" /etc/nftables.d/portmaster-bypass.nft)"
live=yes
for group in pentest libvirt-qemu; do
    gid=$(getent group "$group" | cut -d: -f3) || continue
    nft get element inet portmaster_bypass gids "{ $gid }" > /dev/null 2>&1 || live=no
done
say bypass_live_gids "$live"

if [[ -e "$conf" ]]; then
    say vpn_conf preexisting
    report
    exit 0
fi
say vpn_conf drill
secrets=$(mktemp -d /run/drill-secrets.XXXXXX)
{
    printf '[Interface]\nPrivateKey = %s\nAddress = 10.2.0.2/32\nDNS = 10.2.0.1\n\n' "$(wg genkey)"
    printf '[Peer]\nPublicKey = %s\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = 10.0.2.2:9\n' "$(wg genkey | wg pubkey)"
} > "$secrets/protonvpn-netns.conf"
if DOTFILES_SECRETS=$secrets nu --no-config-file "$repo/scripts/lib/system-apply.nu" module base/protonvpn-netns system; then
    say vpn_module ok
else
    say vpn_module failed
fi
rm -rf "$secrets"

say vpn_links "$(links)"
say vpn_routes "$(ip -n "$ns" route show | sed 's/ *$//' | paste -sd,)"
say vpn_ipv6_off "$(ip netns exec "$ns" sysctl -n net.ipv6.conf.all.disable_ipv6)"
say vpn_route_host "$(ip -n "$ns" route get 10.0.2.2 2> /dev/null | grep -oP 'dev \K\S+')"
say vpn_run_user "$("$run" id -un)"
say vpn_run_ns "$(yesno "$run" ip -o link show wg-protonvpn)"
say vpn_up_curl "$(yesno "$run" curl -s -m 8 "http://$host/beacon/drill-leak-up")"
say vpn_up_dns "$(yesno timeout 30 "$run" getent hosts archlinux.org)"

ip -n "$ns" link set wg-protonvpn down
say vpn_down_route "$(ip -n "$ns" route get 10.0.2.2 > /dev/null 2>&1 && echo yes || echo none)"
say vpn_down_curl "$(yesno "$run" curl -s -m 8 "http://$host/beacon/drill-leak-down")"

ip -n "$ns" link del wg-protonvpn
say vpn_gone_links "$(links)"
say vpn_gone_leak "$(yesno ip netns exec "$ns" curl -s -m 5 "http://$host/beacon/drill-leak-gone")"
say vpn_gone_run "$(refused "$run" true)"
say vpn_gone_shim "$(refused sudo -u "$SUDO_USER" /usr/local/bin/yt-dlp --version)"

systemctl restart protonvpn-netns.service
say vpn_restart_links "$(links)"
systemctl stop protonvpn-netns.service
say vpn_stopped_ns "$(ip netns list | grep -qw "$ns" && echo present || echo absent)"
say vpn_stopped_run "$(refused "$run" true)"

systemctl disable protonvpn-netns.service
rm -f "$conf"
report
