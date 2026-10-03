#!/usr/bin/env bash
# Stage 3: link every configs/*/link.sh; safe to rerun

set -e
cd "$(dirname "$(readlink -f "$0")")"

# progress bars need a tty; re-exec under `script` so pacman/yay render live while logging.
# without a tty (piped, cron) fall through to plain tee.
if [ -z "${_PTY_LOG:-}" ]; then
    export _PTY_LOG=1
    if [ -t 1 ] && command -v script >/dev/null 2>&1; then
        exec script -qe -c "$0 $*" config.log
    fi
    exec > >(tee config.log) 2>&1
fi

export FAILURES_FILE="$(pwd)/FAILURES.config"
: >"$FAILURES_FILE"

source ./scripts/lib/platform.sh
platform_load "$(pwd)"

# guest gating: a non-luca login skips every personal step, link.sh scripts read PERSONAL
source ./scripts/lib/personal.sh
if is_personal; then PERSONAL=1; else PERSONAL=0; fi
export PERSONAL

## SECRETS

# a plugged-in YubiKey pulls and unlocks configs/secrets with two touches, so the links below find them
if is_personal; then ./scripts/yubikey.sh unlock || true; fi

## LINK

grep -qF "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config" /etc/security/pam_env.conf || echo "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config" | sudo tee -a /etc/security/pam_env.conf
grep -qF "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache" /etc/security/pam_env.conf || echo "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache" | sudo tee -a /etc/security/pam_env.conf
grep -qF "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" /etc/security/pam_env.conf || echo "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" | sudo tee -a /etc/security/pam_env.conf
grep -qF "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" /etc/security/pam_env.conf || echo "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" | sudo tee -a /etc/security/pam_env.conf
# zshrc sets GOPATH only interactively; mason's go would create ~/go
grep -qF "GOPATH          DEFAULT=@{HOME}/.go" /etc/security/pam_env.conf || echo "GOPATH          DEFAULT=@{HOME}/.go" | sudo tee -a /etc/security/pam_env.conf
export GOPATH="${HOME}/.go"

# refresh the sudo timestamp before the link loop, which installs configs/sudo (global, 240 min)
sudo -v || true

while IFS= read -r script; do
    dir=$(dirname "$script")
    base=$(basename "$script")
    (
        set -o pipefail
        cd "$dir" && bash "$base" </dev/null 2>&1 | tee "${script}.log"
    ) || echo "$script" >>"$FAILURES_FILE"
# sorted path order: configs/projects needs configs/gh's login first; pacman is linked before the installs
done < <(find "$(pwd)" -type f -name 'link.sh' -not -path "$(pwd)/configs/pacman/*" | sort)
while IFS= read -r script; do
    dir=$(dirname "$script")
    base=$(basename "$script")
    (
        set -o pipefail
        cd "$dir" && python "$base" </dev/null 2>&1 | tee "${script}.log"
    ) || echo "$script" >>"$FAILURES_FILE"
done < <(find "$(pwd)" -type f -name 'link.py' | sort)

## PATCHES

# one-shot fixups for system state an older config left behind; see patches/README.md
./scripts/apply-patches.sh || echo "scripts/apply-patches.sh" >>"$FAILURES_FILE"

## INIT WALLPAPER AND THEME FILES

if command -v git-lfs >/dev/null 2>&1; then
    git lfs pull || echo "git lfs pull" >>"$FAILURES_FILE"
fi

WALLPAPER_SYNC=1 ./scripts/switch-wallpaper.sh ./wallpapers/alena-aenami-darkambient-1k.jpg >/dev/null 2>/dev/null \
    || echo "scripts/switch-wallpaper.sh" >>"$FAILURES_FILE"

## SUMMARY

if [ -s "$FAILURES_FILE" ]; then
    echo "=== FAILED ==="
    cat "$FAILURES_FILE"
    exit 1
fi
echo "All configs linked. Reboot to finish."
rm -f "$FAILURES_FILE"
