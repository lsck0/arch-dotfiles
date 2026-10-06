#!/usr/bin/env bash
# Stage 2: every package of the platform's groups, compiled ones prebuilt from mirror.lsck0.dev

set -e

# progress bars need a tty: re-exec under `script` so pacman/yay render live while logging, plain tee without one
if [ -z "${_PTY_LOG:-}" ]; then
    export _PTY_LOG=1
    # before the re-exec, whose pty stdin would look like a person even under stage.sh's </dev/null
    [ -t 0 ] || export DOTFILES_UNATTENDED=1
    if [ -t 1 ] && command -v script >/dev/null 2>&1; then
        exec script -qe -c "$0 $*" install.log
    fi
    exec > >(tee install.log) 2>&1
fi

export FAILURES_FILE="$PWD/FAILURES.install"
: >"$FAILURES_FILE"

# stage.sh retries an abort but moves on from a run that only logged failures
EXIT_FAILURES=1
EXIT_ABORTED=2
install_finished=0
on_exit() {
    ((install_finished)) || exit "$EXIT_ABORTED"
}
trap on_exit EXIT

## PACKAGES

# every enabled module's manifests collected into one install; names and descriptions live in configs/<module>/{packages,flatpacks,nixpkgs}.txt
source ./scripts/lib/platform.sh
platform_load "$PWD"

# nixpkgs pin, so a Generation installs what it was tested with; bump the rev by hand
NIXPKGS=github:NixOS/nixpkgs/b6c8664de9b6cc07fe5666a29f91884ba81197c4

# read_manifest <file>: one package name per line, comments and blanks dropped
read_manifest() { [[ -f "$1" ]] || return 0; sed -E 's/#.*//; s/[[:space:]]+$//' "$1" | awk 'NF'; }

PACKAGES=()
FLATPAK_PKGS=()
NIX_PKGS=()
for grp in "${PKG_GROUPS[@]}"; do
    mapfile -t -O "${#PACKAGES[@]}"     PACKAGES     < <(read_manifest "configs/$grp/packages.txt")
    mapfile -t -O "${#FLATPAK_PKGS[@]}" FLATPAK_PKGS < <(read_manifest "configs/$grp/flatpacks.txt")
    mapfile -t -O "${#NIX_PKGS[@]}"     NIX_PKGS     < <(read_manifest "configs/$grp/nixpkgs.txt")
done
PACKAGES+=("${EXTRA_PACKAGES[@]}")


## LINK PACMAN CONFIG

# keyring first: pacman/link.sh's lsign needs it, a fresh bootstrap has it empty
sudo pacman-key --init
sudo pacman-key --populate archlinux

# first boot may get here before the network is up; stage.sh reruns install on the next boot, this spares it; wsl has no networkmanager
! command -v nm-online >/dev/null || nm-online -q --timeout=120 || echo "install: still offline after 120s" >&2

# without [lsck0] and its key every sync below would drift off the snapshot, so a failure aborts and stage.sh retries
pushd ./configs/base/pacman
(
    set -o pipefail
    bash ./link.sh 2>&1 | tee ./link.sh.log
) || {
    echo "configs/base/pacman/link.sh" >>"$FAILURES_FILE"
    exit "$EXIT_ABORTED"
}
popd

# a power cut mid-transaction leaves the lock behind, and every retry boot would fail on it
if [[ -e /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null; then sudo rm -f /var/lib/pacman/db.lck; fi

## INSTALLING ALL THE THINGS

source ./scripts/lib/sudo.sh
sudo_keepalive_start

## SOURCES

# [lsck0] (configs/base/pacman/pacman.conf) serves every listed package prebuilt; nothing is built here, gaps are only reported
targets=("${PACKAGES[@]}")

sudo pacman -Syy --noconfirm
# pacman reports every target it can not resolve, by name, provide or group, before it gives up
mapfile -t missing < <(pacman -Sp --noconfirm --print-format '%n' "${targets[@]}" 2>&1 >/dev/null \
    | sed -n 's/^error: target not found: //p')
declare -A MISSING=()
for pkg in "${missing[@]}"; do
    MISSING[$pkg]=1
    echo "not on the mirror: $pkg" >>"$FAILURES_FILE"
done
available=()
for pkg in "${targets[@]}"; do
    [[ -n "${MISSING[$pkg]:-}" ]] || available+=("$pkg")
done
echo "sources: ${#available[@]} packages in one pass, ${#missing[@]} not on the mirror" >&2

# the one download pass: -uu moves pacstrap's packages onto the snapshot, --ask 4 replaces the old lsck0-* names
sudo pacman -Suu --needed --noconfirm --ask 4 "${available[@]}"

## LEDGER

source ./scripts/lib/ledger.sh
# which lsck0 snapshot this machine runs: the pin, the db's publish time and its hash
lsck0_db=/var/lib/pacman/sync/lsck0.db
echo "${LSCK0_SNAPSHOT:-latest} $(date -ur "$lsck0_db" +%FT%TZ) $(sha256sum <"$lsck0_db" | cut -d' ' -f1)" | ledger_set snapshot
# after the install pass, so a dropped package only leaves once whatever replaced it is in
ledger_packages "${targets[@]}" || echo "ledger: removing dropped packages" >>"$FAILURES_FILE"

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

if [[ ${#NIX_PKGS[@]} -gt 0 ]] && command -v nix >/dev/null 2>&1; then
    nix_cmd=(nix --extra-experimental-features 'nix-command flakes')
    sudo systemctl enable --now nix-daemon.socket || echo "nix-daemon.socket" >>"$FAILURES_FILE"
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
