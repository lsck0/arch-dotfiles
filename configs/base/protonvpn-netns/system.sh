#!/usr/bin/env bash
# a network namespace whose only route is a proton wireguard tunnel, and ani-cli routed through it (netns.sh, run.sh);
# the tunnel config is the admin's secret, a wireguard .conf from account.protonvpn.com

# windows owns the network under wsl
[[ "$FORM_FACTOR" != wsl ]] || exit 0

SECRET="$DOTFILES_SECRETS/protonvpn-netns.conf"
CONF=/etc/wireguard/protonvpn-netns.conf
LIB=/usr/local/lib/protonvpn-netns
NS_ETC=/etc/netns/protonvpn
SHIM=/usr/local/bin/ani-cli
SUDOERS=/etc/sudoers.d/20-protonvpn-netns
UNIT=protonvpn-netns.service

# only the machine fact removes it: a run without secrets never undoes one with them
[[ -f "$SECRET" ]] || exit 0
# data only: hooks would run as root; a key masked on download (*****) never makes a tunnel
if ! grep -q '^\[Interface\]' "$SECRET" \
    || grep -qiE '^[[:space:]]*(PreUp|PostUp|PreDown|PostDown|SaveConfig)[[:space:]]*=' "$SECRET" \
    || ! grep -qE '^[[:space:]]*PrivateKey[[:space:]]*=[[:space:]]*[A-Za-z0-9+/]{43}=[[:space:]]*$' "$SECRET"; then
    echo "protonvpn-netns: secrets/protonvpn-netns.conf is no wireguard config with a real PrivateKey (hooks are refused)" >&2
    exit 1
fi

changed=0
cmp -s "$SECRET" "$CONF" || { install -Dm600 -o root -g root "$SECRET" "$CONF"; changed=1; }
file_update netns.sh "$LIB/netns.sh" 755 && changed=1
file_update run.sh "$LIB/run" 755 || true
file_update ani-cli "$SHIM" 755 || true

# ip netns exec binds these over /etc: proton's resolver through the tunnel, and glibc asks it directly instead of the
# main namespace's systemd-resolved (nss resolve reaches it over a unix socket, around the tunnel: a dns leak)
dns=$(sed -n 's/^[[:space:]]*DNS[[:space:]]*=[[:space:]]*//p' "$SECRET" | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -v : | head -1)
printf 'nameserver %s\n' "${dns:-10.2.0.1}" | install -Dm644 /dev/stdin "$NS_ETC/resolv.conf"
sed -E 's/^hosts:.*/hosts: files myhostname dns/' /etc/nsswitch.conf | install -Dm644 /dev/stdin "$NS_ETC/nsswitch.conf"

# validated first, a broken drop-in would lock every admin out
visudo -cf sudoers
install -m440 -o root -g root sudoers "$SUDOERS"

unit_install "$UNIT"
systemctl enable "$UNIT"
if ((changed)) || ! systemctl is-active -q "$UNIT"; then
    systemctl restart "$UNIT"
fi
