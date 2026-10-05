#!/usr/bin/env bash
# undo ufw, which leaves with gufw through install.sh's ledger: toggle-protonvpn.sh ran `ufw enable`, which left ENABLED=yes and could leave ufw chains and an INPUT drop policy inside the iptables-nft filter tables portmaster shares
# also drops the stored firewall toggle state, toggle-firewall.sh now reads the units instead

set -euo pipefail

if command -v ufw >/dev/null 2>&1; then
    # flushes its chains and resets the built-in policies even when nothing is loaded
    sudo ufw --force disable >/dev/null
    sudo systemctl disable --now ufw.service
fi

# chains of a ufw removed while loaded, or the empty primaries `ufw disable` keeps; never whole tables, portmaster and docker live there too
for ipt in iptables ip6tables; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    rules=$(sudo "$ipt" -S)
    mapfile -t chains < <(sed -nE 's/^-N (ufw6?-\S+)$/\1/p' <<<"$rules")
    [[ ${#chains[@]} -gt 0 ]] || continue
    echo "patch: removing ${#chains[@]} ufw chains from $ipt"
    while read -ra rule; do
        sudo "$ipt" -D "${rule[@]:1}"
    done < <(grep -E '^-A (INPUT|OUTPUT|FORWARD) .*-j ufw6?-' <<<"$rules")
    for chain in "${chains[@]}"; do sudo "$ipt" -F "$chain"; done
    for chain in "${chains[@]}"; do sudo "$ipt" -X "$chain"; done
    # ufw's `default deny incoming` set this; left alone it drops every reply portmaster returns
    sudo "$ipt" -P INPUT ACCEPT
done

rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/toggles/firewall"
