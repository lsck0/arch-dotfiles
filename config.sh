#!/usr/bin/env bash
# Stage 3: link every configs/*/link.sh; safe to rerun

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# progress bars need a tty; re-exec under `script` so pacman/yay render live while logging, fall through to plain tee without a tty (piped, cron)
if [ -z "${_PTY_LOG:-}" ]; then
    export _PTY_LOG=1
    # before the re-exec, whose pty stdin would look like a person even under stage.sh's </dev/null
    [ -t 0 ] || export DOTFILES_UNATTENDED=1
    if [ -t 1 ] && command -v script >/dev/null 2>&1; then
        exec script -qe -c "$0 $*" config.log
    fi
    exec > >(tee config.log) 2>&1
fi

export FAILURES_FILE="$PWD/FAILURES.config"
: >"$FAILURES_FILE"
fail() { echo "$1" >>"$FAILURES_FILE"; }

source ./scripts/lib/platform.sh
platform_load "$PWD"

# guest gating: a non-luca login skips every personal step, link.sh scripts read PERSONAL
source ./scripts/lib/personal.sh
if is_personal; then PERSONAL=1; else PERSONAL=0; fi
export PERSONAL

source ./scripts/lib/sudo.sh
sudo_keepalive_start

## SECRETS

# a plugged-in YubiKey pulls and unlocks configs/secrets with two touches, so the links below find them
if is_personal; then ./scripts/yubikey.sh unlock || fail "scripts/yubikey.sh unlock"; fi

## LINK

# zshrc sets GOPATH only interactively; mason's go would create ~/go
for line in "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config" "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache" \
    "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" \
    "GOPATH          DEFAULT=@{HOME}/.go"; do
    grep -qF "$line" /etc/security/pam_env.conf || echo "$line" | sudo tee -a /etc/security/pam_env.conf >/dev/null
done
export GOPATH="${HOME}/.go"

# sorted path order: configs/projects needs configs/gh's login first; pacman is linked by install.sh before the installs
while IFS= read -r script; do
    runner=bash
    [[ "$script" == *.py ]] && runner=python
    (cd "$(dirname "$script")" && "$runner" "$(basename "$script")" </dev/null 2>&1 | tee "${script}.log") || fail "$script"
done < <(find "$PWD" -type f \( -name link.sh -o -name link.py \) -not -path "$PWD/configs/pacman/*" | sort)

## PRUNE

# root runs nothing from the checkout, and a deleted script leaves no name behind
find /usr/local/bin -maxdepth 1 -type l -lname "$PWD/*" -exec sudo rm -f {} + || fail "prune /usr/local/bin"
find "$HOME" "$HOME/.local/bin" -maxdepth 1 -xtype l -lname "$PWD/*" -delete || fail "prune ~ and ~/.local/bin"

## PATCHES

# one-shot fixups for system state an older config left behind; see patches/README.md
./scripts/apply-patches.sh || fail "scripts/apply-patches.sh"

## LEDGER

# after every link.sh and patch, so a unit is owned or dropped by what this run left enabled
source ./scripts/lib/ledger.sh
ledger_units "$PWD" || fail "ledger: disabling dropped units"

## INIT WALLPAPER AND THEME FILES

if command -v git-lfs >/dev/null 2>&1; then
    git lfs pull || fail "git lfs pull"
fi

WALLPAPER_SYNC=1 ./scripts/switch-wallpaper.sh ./wallpapers/alena-aenami-darkambient-1k.jpg >/dev/null \
    || fail "scripts/switch-wallpaper.sh"

## BOOT

# last, so every initramfs, cmdline and grub change of this run is rebuilt once in one order, then signed and verified
source ./configs/boot/boot-menu/common.sh
boot_commit || fail "boot barrier (configs/boot/boot-menu/common.sh)"

## SUMMARY

if [ -s "$FAILURES_FILE" ]; then
    echo "=== FAILED ==="
    cat "$FAILURES_FILE"
    exit 1
fi
echo "All configs linked. Reboot to finish."
rm -f "$FAILURES_FILE"
