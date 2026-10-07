#!/usr/bin/env bash
# Stage 2: for an admin, every package of the platform's groups through scripts/lib/system-apply.sh from the root copy,
# compiled ones prebuilt from mirror.lsck0.dev; then this user's rust, flatpak and nix parts. --user skips the system part
# usage: install.sh [--user]

set -e
self=$(readlink -f "$0")
cd "${self%/*}"

# progress bars need a tty: re-exec under `script` so pacman/yay render live while logging, plain tee without one
if [ -z "${_PTY_LOG:-}" ]; then
    export _PTY_LOG=1
    # before the re-exec, whose pty stdin would look like a person even under stage.sh's </dev/null
    [ -t 0 ] || export DOTFILES_UNATTENDED=1
    if [ -t 1 ] && command -v script >/dev/null 2>&1; then
        # script runs the command through a shell: an absolute path, every word quoted
        exec script -qe -c "$(printf '%q ' "$self" "$@")" install.log
    fi
    exec > >(tee install.log) 2>&1
fi

export DOTFILES="$PWD"
export FAILURES_FILE="$PWD/FAILURES.install"
: >"$FAILURES_FILE"

# stage.sh retries an abort but moves on from a run that only logged failures; system-apply.sh uses the same codes
EXIT_FAILURES=1
EXIT_ABORTED=2
install_finished=0
on_exit() {
    ((install_finished)) || exit "$EXIT_ABORTED"
}
trap on_exit EXIT

user_only=0
case "${1:-}" in
    "") ;;
    --user) user_only=1 ;;
    *) echo "usage: install.sh [--user]" >&2; exit 1 ;;
esac

# nixpkgs pin, so a Generation installs what it was tested with; bump the rev by hand
NIXPKGS=github:NixOS/nixpkgs/b6c8664de9b6cc07fe5666a29f91884ba81197c4

source ./scripts/lib/platform.sh
source ./scripts/lib/system.sh
platform_load "$PWD"

## SYSTEM

# an admin refreshes the root copy and installs from it; sudo resets the env, so unattended travels as a flag
if ((!user_only)) && id -nG | grep -qw wheel; then
    if ! system_copy "$PWD" "$SYSTEM_REPO" sudo; then
        echo "system_copy: the root copy was not refreshed" >>"$FAILURES_FILE"
        exit "$EXIT_ABORTED"
    fi
    status=0
    sudo "$SYSTEM_REPO/scripts/lib/system-apply.sh" install ${DOTFILES_UNATTENDED:+--unattended} || status=$?
    if ((status == EXIT_ABORTED)); then
        echo "scripts/lib/system-apply.sh install aborted" >>"$FAILURES_FILE"
        exit "$EXIT_ABORTED"
    elif ((status != 0)); then
        echo "scripts/lib/system-apply.sh install" >>"$FAILURES_FILE"
        cat "$SYSTEM_STATE/FAILURES" >>"$FAILURES_FILE" 2>/dev/null || true
    fi
fi

## USER

mapfile -t FLATPAK_PKGS < <(platform_packages flatpacks)
mapfile -t NIX_PKGS < <(platform_packages nixpkgs)

# stable only, a project pins nightly in its rust-toolchain.toml
if command -v rustup >/dev/null 2>&1; then
    rustup default stable || echo "rustup default stable" >>"$FAILURES_FILE"
fi

# user scope: a system deploy needs a polkit agent the unattended chain does not have
if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]] && command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
        && flatpak install --user --noninteractive flathub "${FLATPAK_PKGS[@]}" \
        || echo "flatpak install --user ${FLATPAK_PKGS[*]}" >>"$FAILURES_FILE"
fi

# the daemon socket is system-apply's
if [[ ${#NIX_PKGS[@]} -gt 0 ]] && command -v nix >/dev/null 2>&1; then
    nix_cmd=(nix --extra-experimental-features 'nix-command flakes')
    # nix profile add stacks a duplicate on every rerun, so only the names the profile lacks
    mapfile -t nix_missing < <(comm -23 <(printf '%s\n' "${NIX_PKGS[@]}" | sort) \
        <("${nix_cmd[@]}" profile list --json | jq -r '.elements | keys[]' | sort))
    if ((${#nix_missing[@]})); then
        "${nix_cmd[@]}" profile add "${nix_missing[@]/#/$NIXPKGS#}" \
            || echo "nix profile add ${nix_missing[*]}" >>"$FAILURES_FILE"
    fi
fi

## SUMMARY

install_finished=1
if [ -s "$FAILURES_FILE" ]; then
    echo "=== FAILED ==="
    cat "$FAILURES_FILE"
    exit "$EXIT_FAILURES"
fi
echo "All packages installed. Next: reboot, then ./config.sh"
rm -f "$FAILURES_FILE"
