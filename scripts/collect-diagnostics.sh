#!/usr/bin/env bash
# no-errexit: a failing probe is a finding to record, the rest must still be collected
set -uo pipefail
# the bundle gets shared: only its owner may read it
umask 077

case "${1:-}" in
    -h | --help)
        echo "usage: collect-diagnostics [dest]: logs, journals, network and dot state into dest/diag-<host>-<time>/"
        exit 0
        ;;
esac
self=$(dirname "$(realpath "$0")")
if [[ -n "${1:-}" ]]; then
    dest=$1
elif [[ -f "$self/dot.nu" ]]; then
    # never into the checkout: dot sync would commit it
    dest=$HOME
else
    dest=$self
fi
out="$dest/diag-$(cat /etc/hostname 2> /dev/null || uname -n)-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out" || exit 1

if ((EUID == 0)); then
    as_root=()
elif sudo -n true 2> /dev/null || sudo -v; then
    as_root=(sudo -n)
else
    as_root=()
    echo "collect-diagnostics: no sudo, root-only commands are skipped" >&2
fi

run() {
    local file=$1
    shift
    {
        echo "\$ $*"
        if command -v "$1" > /dev/null 2>&1; then timeout 60 "$@" 2>&1; else echo "(not installed)"; fi
        echo
    } >> "$out/$file.txt"
}
root() {
    local file=$1
    shift
    if ((EUID == 0)) || ((${#as_root[@]})); then run "$file" "${as_root[@]}" "$@"; else echo "\$ $* (skipped, no root)" >> "$out/$file.txt"; fi
}
grab() {
    local f
    for f in "$@"; do [[ -r "$f" ]] && cp -rL "$f" "$out/files/" 2> /dev/null; done
}
root_grab() {
    if ((EUID == 0)) || ((${#as_root[@]})); then
        "${as_root[@]}" cp -rL --no-preserve=mode,ownership "$@" "$out/files/" 2> /dev/null
        "${as_root[@]}" chown -R "$(id -u):$(id -g)" "$out/files"
    fi
}
mkdir -p "$out/files"

echo "collecting into $out" >&2

run system date -Is
run system uname -a
run system cat /etc/os-release
run system hostnamectl
run system uptime
run system cat /proc/cmdline
run system timedatectl
run system localectl
run hardware lscpu
run hardware free -h
run hardware lspci -nnk
run hardware lsusb
run hardware lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS,TRAN,MODEL
run hardware findmnt
run hardware df -h
run hardware lsmod
run hardware cat /proc/swaps

run boot bootctl status
root boot sbctl status
root boot sbctl verify
run boot systemd-analyze
run boot systemd-analyze blame
run boot systemd-analyze critical-chain
root boot dmesg --level=err,warn
run boot journalctl --list-boots --no-pager

run units systemctl --failed --no-pager
run units systemctl --user --failed --no-pager
run units systemctl list-units --state=failed,activating,auto-restart --all --no-pager
run units systemctl list-jobs --no-pager
run units systemctl --user list-units --state=failed,activating,auto-restart --all --no-pager

run network ip -br link
run network ip addr
run network ip route
run network ip -6 route
run network ip rule
run network rfkill
run network nmcli general
run network nmcli radio
run network nmcli device
run network nmcli -f NAME,TYPE,DEVICE,AUTOCONNECT,ACTIVE connection
run network iw dev
run network resolvectl status
run network cat /etc/resolv.conf
run network systemctl status NetworkManager iwd wpa_supplicant systemd-resolved systemd-networkd --no-pager
run network ping -c 3 -W 2 1.1.1.1
run network ping -c 3 -W 2 archlinux.org
run network curl -sS -m 10 -o /dev/null -w '%{http_code} %{time_total}s %{speed_download}B/s\n' https://mirror.lsck0.dev/
root network nft list ruleset
root network iptables-save
root network ss -tunap
run network systemctl status sshd portmaster --no-pager

for dev in /sys/class/net/*; do
    link=${dev##*/}
    [[ $link == lo ]] && continue
    run links echo "== $link: $(cat "$dev/operstate" 2> /dev/null), mac $(cat "$dev/address" 2> /dev/null)"
    run links ethtool -P "$link"
    gateway=$(ip -4 route show default dev "$link" 2> /dev/null | awk '{print $3; exit}')
    [[ -n $gateway ]] && run links ip neigh show "$gateway" dev "$link"
    profile=$(nmcli -g GENERAL.CONNECTION device show "$link" 2> /dev/null)
    [[ -n $profile ]] && run links nmcli -f connection.id,connection.type,802-11-wireless.ssid,802-11-wireless.cloned-mac-address,802-3-ethernet.cloned-mac-address,ipv4.method,ipv4.dns,ipv4.ignore-auto-dns,ipv6.method connection show "$profile"
done
run links nmcli -f GENERAL.DEVICE,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.DNS device show
grab /run/home-network /etc/NetworkManager/home-gateways /etc/NetworkManager/homelab.env
root_grab /etc/NetworkManager/dispatcher.d

for name in archlinux.org example.com; do
    run dns getent ahosts "$name"
    run dns resolvectl query "$name"
done
run dns resolvectl statistics
run dns resolvectl dns
servers=$( (
    resolvectl dns 2> /dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}'
    nmcli -g IP4.DNS device show 2> /dev/null | tr '|' '\n'
    grep -oE '^nameserver +\S+' /etc/resolv.conf | awk '{print $2}'
    printf '%s\n' 1.1.1.1 9.9.9.9
) | grep -vE '^127\.|^$' | sort -u)
for server in $servers; do
    run dns dig +time=3 +tries=1 archlinux.org "@$server"
    run dns dig +time=3 +tries=1 +tcp archlinux.org "@$server"
    run dns dig +time=3 +tries=1 +tls archlinux.org "@$server"
done
run dns journalctl -b -u systemd-resolved -u portmaster --no-pager -n 300

run packages pacman -Qkq
run packages pacman -Qdtq
run packages cat /etc/pacman.conf
run packages cat /etc/pacman.d/mirrorlist
grab /var/log/pacman.log

run journal journalctl -b -p warning --no-pager
run journal_user journalctl --user -b -p warning --no-pager
run journal_net journalctl -b -u NetworkManager -u iwd -u wpa_supplicant -u nftables -u portmaster --no-pager
root journal_kernel journalctl -k -b --no-pager
root apparmor journalctl -k -b --no-pager -g 'apparmor="DENIED"'
root apparmor aa-status
run journal_full journalctl -b --no-pager -o short-monotonic
run journal_prev journalctl -b -1 --no-pager -o short-monotonic
run journal_user_full journalctl --user -b --no-pager -o short-monotonic
run coredumps coredumpctl list --no-pager
for unit in $(systemctl --failed --plain --no-legend 2> /dev/null | awk '{print $1}'); do
    run "failed_$unit" systemctl status "$unit" --no-pager -l
    run "failed_$unit" journalctl -b -u "$unit" --no-pager
done
for unit in $(systemctl --user --failed --plain --no-legend 2> /dev/null | awk '{print $1}'); do
    run "failed_user_$unit" systemctl --user status "$unit" --no-pager -l
    run "failed_user_$unit" journalctl --user -b -u "$unit" --no-pager
done
if command -v zstd > /dev/null; then
    for boot in 0 -1 -2 -3 -4; do
        "${as_root[@]}" journalctl -b "$boot" -o export 2> /dev/null | zstd -q -T0 > "$out/journal-boot$boot.export.zst"
        [[ -s "$out/journal-boot$boot.export.zst" ]] || rm -f "$out/journal-boot$boot.export.zst"
    done
fi
grab /var/log/Xorg.0.log
root_grab /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d /etc/iwd/main.conf /etc/nftables.conf \
    /etc/systemd/network /etc/modprobe.d /etc/mkinitcpio.conf /etc/kernel/cmdline /etc/fstab /etc/crypttab

repo=$(dirname "$(dirname "$(realpath "$HOME/.local/bin/dot" 2> /dev/null)")" 2> /dev/null)
[[ -f "$repo/scripts/dot.nu" ]] || repo=/var/lib/dotfiles/repo
run dot git -C "$repo" log -3 --format='%h %ad %s'
run dot git -C "$repo" status --short
run dot dot status
run dot dot log
run dot dot log --level WARN
grab "$repo"/FAILURES.* "$repo"/install.log "$repo"/config.log "$repo"/stage.log
grab "$HOME/.local/state/dotfiles/crash.json" "$HOME/.config/dotfiles/profile.nuon"
grab "$HOME/.local/state/dotfiles/runs" "$HOME/.local/state/dotfiles/ledger"
root dot cat /var/lib/dotfiles/crash.json
root dot ls -la /etc/sudoers.d
root_grab /var/lib/dotfiles-stage /var/lib/dotfiles/runs

run session wpctl status
run session upower -d
run session sensors
run session loginctl list-sessions
# credentials from direnv or the shell stay out of a bundle meant to be handed out
env | sed -E 's/^([^=]*(TOKEN|KEY|SECRET|PASSWORD|PASS|CREDENTIAL|AUTH|COOKIE)[^=]*)=.*/\1=<redacted>/I' > "$out/session-env.txt"

run desktop hyprctl version
run desktop hyprctl monitors
run desktop journalctl --user -u quickshell -b --no-pager -o cat
newest() {
    local f best=
    for f in "$1"/*/"$2"; do [[ -e "$f" && (-z "$best" || "$f" -nt "$best") ]] && best=$f; done
    [[ -n "$best" ]] && grab "$best"
}
newest "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" hyprland.log
newest "${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell/by-id" log.log

sync
echo "done: $out ($(du -sh "$out" | cut -f1))" >&2
