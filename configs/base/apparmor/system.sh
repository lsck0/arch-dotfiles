#!/usr/bin/env bash

# windows owns kernel, boot, drivers, power, audio and network under wsl; nothing here applies
[[ "$FORM_FACTOR" != wsl ]] || exit 0

source "$DOTFILES/configs/base/boot/common.sh"

# the kernel's CONFIG_LSM default with apparmor before bpf; active after the next reboot
if esp_supported; then
    kernel_cmdline_set lsm=landlock,lockdown,yama,integrity,apparmor,bpf
fi
systemctl enable apparmor.service

# apparmor.d's install guide: the compiled policy cached where systemd (+APPARMOR) loads it before the first unit,
# so every profile is in place before any session starts
mkdir -p /etc/apparmor/earlypolicy
for line in write-cache 'cache-loc /etc/apparmor/earlypolicy/' Optimize=compress-fast; do
    grep -qxF "$line" /etc/apparmor/parser.conf || echo "$line" >>/etc/apparmor/parser.conf
done

MANUAL=/etc/apparmor/flags.d/manual.conf
# profiles.conf's rows for apparmor.d to build, the module's own profiles/ are installed below
upstream() { awk 'FILENAME != "profiles.conf" {own[$0]; next} /^[^#]/ && NF && !($1 in own)' <(ls profiles) profiles.conf; }
# "<profile> <mode>" in effect: the baseline, then the `aa` command's manual choices
modes() { { cat profiles.conf; cat "$MANUAL" 2>/dev/null || true; } | awk '/^[^#]/ && NF >= 2 {m[$1] = $2} END {for (p in m) print p, m[p]}'; }

install -Dm644 modes /etc/apparmor/modes
# baseline, owned by the dotfiles. The `aa` command (link.sh) layers per-app choices into a sibling manual.conf
# in these same drop-in dirs, which this run leaves untouched, so manual decisions survive config runs.
upstream | install -Dm644 /dev/stdin /etc/apparmor/flags.d/dotfiles.conf
upstream | cut -d' ' -f1 | install -Dm644 /dev/stdin /etc/apparmor/include.d/dotfiles.conf
# apparmor.d assumes capitalized xdg dirs, configs/base/xdg's are lowercase; core/syncthing's folder is ~/sync
{
    sed -n 's|^\(XDG_[A-Z]*_DIR\)="[$]HOME/\(.*\)"$|@{\1}+="\2"|p' "$DOTFILES/configs/base/xdg/user-dirs.dirs"
    echo '@{XDG_SYNC_DIR}+="sync"'
} | install -Dm644 /dev/stdin /etc/apparmor.d/tunables/xdg-user-dirs.d/apparmor.d.d/dotfiles
# all below builds on apparmor.d's variables and abstractions; without them it would not compile, so it stays off
own=()
if [[ -e /etc/apparmor.d/abstractions/base-strict ]]; then
    # rules the module's profiles share, and drop-ins that extend apparmor.d's (local/<profile>); @{HOME}: every
    # user's own checkout, the profiles are shared by all of them
    install -Dm644 -t /etc/apparmor.d/abstractions/dotfiles abstractions/*
    install -Dm644 -t /etc/apparmor.d/local local/*
    # every gui profile reads the ~/.config link targets in the checkout through the abstractions it already includes
    for hook in desktop fonts qt5 qt6 kde; do
        printf '  include <abstractions/dotfiles/config-links>\n' |
            install -Dm644 /dev/stdin "/etc/apparmor.d/abstractions/${hook}.d/dotfiles-config-links"
    done
    # every QtWebEngine profile builds on apparmor.d's chromium abstraction
    printf '  include <abstractions/dotfiles/qtwebengine>\n' |
        install -Dm644 /dev/stdin /etc/apparmor.d/abstractions/common/chromium.d/dotfiles-qtwebengine
    # the module's own profiles, where apparmor.d has none, in their mode: enforce is the header as written
    for src in profiles/*; do
        mode=$(modes | awk -v p="${src##*/}" '$1 == p {print $2}')
        if [[ "$mode" == complain || "$mode" == unconfined ]]; then
            sed -E "/^profile /s/flags=\(/flags=($mode,/" "$src"
        else
            cat "$src"
        fi | install -Dm644 /dev/stdin "/etc/apparmor.d/${src##*/}"
        own+=("${src##*/}")
    done
else
    echo "apparmor: apparmor.d is not installed, the module's profiles and drop-ins stay off" >&2
fi

# apparmor.d's pacman hook reruns aa-install on every transaction, this run picks up the config above; a failed
# build leaves the loaded policy alone, so it is logged and the check below names what is off
if command -v aa-install >/dev/null 2>&1; then
    aa-install --install --no-reload || echo "apparmor: aa-install failed, the profiles keep their last build" >&2
fi

# from the next boot on, once lsm= has the kernel run apparmor
if [[ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" != Y ]]; then
    echo "apparmor: not active in this kernel yet, the profiles load on the next boot" >&2
    exit 0
fi
# one reload through the policy cache loads all of the above; a profile that fails to compile is logged by the
# service and keeps its previous state, the others load
systemctl reload-or-restart apparmor.service || echo "apparmor: reload failed, see journalctl -u apparmor" >&2

# every deployed profile loaded in its mode, else this module fails (FAILURES) with everything above applied
deployed=$({ aa-install --list 2>/dev/null || true; printf '%s\n' "${own[@]}"; } | sed 's|.*/||; s|\.apparmor\.d$||')
failed=0
while read -r name want; do
    grep -qxF "$name" <<<"$deployed" || continue
    have=$(awk -v p="$name" '$1 == p {gsub(/[()]/, "", $2); print $2}' /sys/kernel/security/apparmor/profiles)
    if [[ "$have" != "$want" ]]; then
        echo "apparmor: $name is ${have:-not loaded}, expected $want" >&2
        failed=1
    fi
done < <(modes)
exit "$failed"
