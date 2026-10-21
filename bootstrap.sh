#!/usr/bin/env bash
set -euo pipefail
DOTFILES_URL=https://github.com/lsck0/arch-dotfiles.git
CLONE_DIR=/tmp/arch-dotfiles
SIGNING_KEY_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
SIGNING_KEY_FILE=configs/core/gnupg/luca-sandrock.pub.asc
COW_MIN_MIB=1024

if [[ -d /run/archiso ]] && grep -q 'archisobasedir=' /proc/cmdline; then
    :
elif grep -qi microsoft /proc/sys/kernel/osrelease; then
    :
else
    echo "bootstrap: run this from the Arch ISO or inside WSL" >&2
    exit 1
fi

[[ -z "${BOOTSTRAP_KEYMAP:-}" ]] || loadkeys "$BOOTSTRAP_KEYMAP"
if [[ -d /run/archiso ]]; then
    (($(df --output=size -BM /run/archiso/cowspace | tail -1 | tr -dc 0-9) >= COW_MIN_MIB)) ||
        mount -o "remount,size=${COW_MIN_MIB}M" /run/archiso/cowspace
    systemctl start pacman-init.service
    pacman -Sy --noconfirm --needed archlinux-keyring
    pacman -S --noconfirm --needed glibc nushell git gnupg
else
    pacman-key --init && pacman-key --populate archlinux
    pacman -Sy --noconfirm --needed archlinux-keyring
    pacman -Su --noconfirm --needed nushell git gnupg sudo zsh
fi

repo=$(dirname "$(readlink -f "${BASH_SOURCE[0]:-/}")")
if [[ ! -f "$repo/scripts/dot.nu" ]]; then
    rm -rf "$CLONE_DIR" && git clone "$DOTFILES_URL" "$CLONE_DIR" && repo=$CLONE_DIR
    if [[ "${BOOTSTRAP_INSECURE:-0}" != 1 ]]; then
        gnupg=$(mktemp -d)
        GNUPGHOME=$gnupg gpg --batch -q --import "$repo/$SIGNING_KEY_FILE"
        if ! status=$(GNUPGHOME=$gnupg git -C "$repo" verify-commit --raw HEAD 2>&1) ||
            ! grep -q "^\[GNUPG:\] VALIDSIG .* $SIGNING_KEY_FINGERPRINT\$" <<< "$status"; then
            echo "bootstrap: $DOTFILES_URL HEAD is not signed by $SIGNING_KEY_FINGERPRINT. BOOTSTRAP_INSECURE=1 skips this check." >&2
            exit 1
        fi
    fi
fi
entry=bootstrap && [[ "${LSCK0_INSTALL:-0}" != 1 ]] || entry=iso-install
if { : < /dev/tty; } 2> /dev/null; then exec nu --no-config-file "$repo/scripts/dot.nu" internal "$entry" "$@" < /dev/tty; fi
exec nu --no-config-file "$repo/scripts/dot.nu" internal "$entry" "$@" < /dev/null
