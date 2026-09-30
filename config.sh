#!/usr/bin/env bash
# Stage 3: link every configs/*/link.sh; safe to rerun

set -e
cd "$(dirname "$(readlink -f "$0")")"
exec > >(tee "config.log") 2>&1

export FAILURES_FILE="$(pwd)/FAILURES.config"
: >"$FAILURES_FILE"

source ./scripts/lib/platform.sh
platform_load "$(pwd)"

## SECRETS

# a plugged-in YubiKey pulls and unlocks configs/secrets with two touches, so the links below find them
./scripts/yubikey.sh unlock || true

## LINK

grep -qF "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config" /etc/security/pam_env.conf || echo "XDG_CONFIG_HOME DEFAULT=@{HOME}/.config" | sudo tee -a /etc/security/pam_env.conf
grep -qF "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache" /etc/security/pam_env.conf || echo "XDG_CACHE_HOME  DEFAULT=@{HOME}/.cache" | sudo tee -a /etc/security/pam_env.conf
grep -qF "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" /etc/security/pam_env.conf || echo "XDG_DATA_HOME   DEFAULT=@{HOME}/.local/share" | sudo tee -a /etc/security/pam_env.conf
grep -qF "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" /etc/security/pam_env.conf || echo "XDG_STATE_HOME  DEFAULT=@{HOME}/.local/state" | sudo tee -a /etc/security/pam_env.conf

# refresh the sudo timestamp before the link loop, which installs configs/sudo (global, 240 min)
sudo -v || true

while IFS= read -r script; do
    dir=$(dirname "$script")
    base=$(basename "$script")
    (
        set -o pipefail
        cd "$dir" && bash "$base" </dev/null 2>&1 | tee "${script}.log"
    ) || echo "$script" >>"$FAILURES_FILE"
done < <(find "$(pwd)" -type f -name 'link.sh' -not -path "$(pwd)/configs/pacman/*") # pacman linked before the installs
while IFS= read -r script; do
    dir=$(dirname "$script")
    base=$(basename "$script")
    (
        set -o pipefail
        cd "$dir" && python "$base" </dev/null 2>&1 | tee "${script}.log"
    ) || echo "$script" >>"$FAILURES_FILE"
done < <(find "$(pwd)" -type f -name 'link.py')

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
