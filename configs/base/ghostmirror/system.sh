#!/usr/bin/env bash

MIRRORLIST=/etc/pacman.d/mirrorlist
HOMELAB_MIRROR=10.100.0.109

# the committed ranking seeds a fresh install or replaces the old link into the checkout; the timers keep it current
if [[ -L "$MIRRORLIST" ]] || ! grep -q '^# lastsync' "$MIRRORLIST"; then
    # only a HOMELAB machine reaches the homelab mirror
    if [[ -n "$HOMELAB" ]]; then
        install -Dm644 mirrorlist "$MIRRORLIST"
    else
        grep -vF "$HOMELAB_MIRROR" mirrorlist | install -Dm644 /dev/stdin "$MIRRORLIST"
    fi
elif [[ -z "$HOMELAB" ]] && grep -qF "$HOMELAB_MIRROR" "$MIRRORLIST"; then
    # stripped in place, ranking kept; mirrorlist-update.sh keeps only a homelab line that is present
    grep -vF "$HOMELAB_MIRROR" "$MIRRORLIST" | install -m644 /dev/stdin "$MIRRORLIST.new"
    mv -f "$MIRRORLIST.new" "$MIRRORLIST"
elif [[ -n "$HOMELAB" ]] && ! grep -qF "$HOMELAB_MIRROR" "$MIRRORLIST"; then
    # a machine that became HOMELAB after its list was ranked: the committed homelab line on top, ranking kept
    { grep -F "$HOMELAB_MIRROR" mirrorlist; echo; cat "$MIRRORLIST"; } | install -m644 /dev/stdin "$MIRRORLIST.new"
    mv -f "$MIRRORLIST.new" "$MIRRORLIST"
fi

# root writes the mirrorlist, so root runs the ranking from its own copy; weekly sort re-ranks, monthly rebuild finds new mirrors
install -Dm755 mirrorlist-update.sh /usr/local/bin/mirrorlist-update
unit_install ghostmirror.service ghostmirror.timer ghostmirror-refresh.service ghostmirror-refresh.timer
systemctl enable --now ghostmirror.timer ghostmirror-refresh.timer
