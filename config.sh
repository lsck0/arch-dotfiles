#!/usr/bin/env bash
# Stage 3: the user layer (every link.sh of the platform's groups) and, for an admin, the system layer through
# scripts/lib/system-apply.sh from the root copy; safe to rerun. --user skips the system layer
# usage: config.sh [--user]

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export DOTFILES="$PWD"
[[ -z ${DIRENV_DIR-} ]] || { echo "run outside a direnv directory" >&2; exit 1; }

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

user_only=0
case "${1:-}" in
    "") ;;
    --user) user_only=1 ;;
    *) echo "usage: config.sh [--user]" >&2; exit 1 ;;
esac

export FAILURES_FILE="$PWD/FAILURES.config"
: >"$FAILURES_FILE"
fail() { echo "$1" >>"$FAILURES_FILE"; }

source ./scripts/lib/platform.sh
source ./scripts/lib/module.sh
source ./scripts/lib/ledger.sh
source ./scripts/lib/system.sh
platform_load "$PWD"

## PATCHES

# one-shot fixups of this user's state, before anything personal: patch 22 creates the profile; see patches/README.md
./scripts/lib/apply-patches.sh || fail "scripts/lib/apply-patches.sh"
profile_load

## SECRETS

# a plugged-in YubiKey pulls and unlocks secrets with two touches, so the system secrets and the links below find them
if profile_has secrets; then ./scripts/lib/yubikey.sh unlock || fail "scripts/lib/yubikey.sh unlock"; fi

## SYSTEM

# an admin refreshes the root copy and runs the system layer from it; the plaintext secrets it needs go along as data.
# sudo resets the env, so unattended travels as a flag; the ledger's prompts read /dev/tty, stdin carries the tar
if ((!user_only)) && id -nG | grep -qw wheel; then
    if system_copy "$PWD" "$SYSTEM_REPO" sudo; then
        system_secrets=()
        for name in "${SYSTEM_SECRETS[@]}" ${WIREGUARD:+"$WIREGUARD"}; do
            if secret_is_plaintext "secrets/$name"; then system_secrets+=("$name"); fi
        done
        secrets_dir=.
        [[ ! -d secrets ]] || secrets_dir=secrets
        if ! { ((${#system_secrets[@]} == 0)) || printf '%s\0' "${system_secrets[@]}"; } \
            | tar -C "$secrets_dir" -c --null -T - -f - \
            | sudo "$SYSTEM_REPO/scripts/lib/system-apply.sh" config ${DOTFILES_UNATTENDED:+--unattended}; then
            fail "scripts/lib/system-apply.sh config"
            cat "$SYSTEM_STATE/FAILURES" >>"$FAILURES_FILE" 2>/dev/null || true
        fi
    else
        fail "system_copy: the root copy was not refreshed, system layer skipped"
    fi
fi

## LINK

# zshrc sets GOPATH only interactively; mason's go would create ~/go
export GOPATH="${HOME}/.go"

# only the platform's modules link; the module gate replaces the old per-config guards
module_dirs=()
for grp in "${PKG_GROUPS[@]}"; do module_dirs+=("$PWD/configs/$grp"); done
root_dirs=("$PWD/scripts" "$PWD/skills")
# the weblinks are luca's own bookmarks: homelab, his bank
if profile_has homelab; then root_dirs+=("$PWD/weblinks"); fi

# sorted path order: configs/programming/projects needs configs/base/gh's login first
while IFS= read -r script; do
    module_run "$script" || fail "$script"
done < <(find "${module_dirs[@]}" "${root_dirs[@]}" -type f \( -name link.sh -o -name link.py \) | sort)

## PRUNE

# a deleted script leaves no name behind
find "$HOME" "$HOME/.local/bin" -maxdepth 1 -xtype l -lname "$PWD/*" -delete || fail "prune ~ and ~/.local/bin"

## LEDGER

# after every link.sh, so a user unit is owned or dropped by what this run left enabled
ledger_units "$PWD" || fail "ledger: disabling dropped units"

## INIT WALLPAPER AND THEME FILES

if command -v git-lfs >/dev/null 2>&1; then
    git lfs pull || fail "git lfs pull"
fi

# a bare name resolves to the secrets copy when unlocked
wp=$(readlink -f ~/.cache/wal/wallpaper 2>/dev/null) && [[ -f $wp ]] || wp=alena-aenami-darkambient-1k.jpg
stamp=$(git ls-files -s configs/base/wallust configs/base/themes scripts/switch-wallpaper.sh | sha1sum)
if [[ ! -e ~/.cache/wal/wallpaper || "$(cat ~/.cache/wal/.theme-stamp 2>/dev/null)" != "$stamp" ]]; then
    WALLPAPER_SYNC=1 ./scripts/switch-wallpaper.sh set "$wp" >/dev/null && echo "$stamp" >~/.cache/wal/.theme-stamp \
        || fail "scripts/switch-wallpaper.sh"
fi

## SUMMARY

if [ -s "$FAILURES_FILE" ]; then
    echo "=== FAILED ==="
    cat "$FAILURES_FILE"
    exit 1
fi
echo "All configs linked. Reboot to finish."
rm -f "$FAILURES_FILE"
