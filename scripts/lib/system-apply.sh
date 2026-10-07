#!/usr/bin/env bash
# the system layer's one root entry, run by install.sh and config.sh through sudo and only from the root-owned copy:
# install = keyring, pacman config and every package of the platform; config = every system.sh, patches, units, boot.
# config reads the admin's plaintext secrets as a tar on stdin, as data only. failures in $SYSTEM_STATE/FAILURES
# usage: system-apply.sh <install|config> [--unattended]

set -euo pipefail
umask 022

# install.sh's codes: stage.sh retries an abort but moves on from a run that only logged failures
EXIT_FAILURES=1
EXIT_ABORTED=2
OFFLINE_WAIT_S=120
LSCK0_DB=/var/lib/pacman/sync/lsck0.db
PACMAN_LOCK=/var/lib/pacman/db.lck
PACMAN_MODULE=configs/base/pacman/system.sh
YUBIKEY_MODULE=configs/base/yubikey/system.sh
ADDUSER_LINK=/usr/local/bin/adduser-dotfiles

die() { echo "system-apply: $*" >&2; exit "$EXIT_ABORTED"; }

cd "$(dirname "$(readlink -f "$0")")/../.."
source ./scripts/lib/system.sh
# root only ever runs root-owned files: refuse a checkout or a copy anyone else could have written
((EUID == 0)) || die "run as root"
[[ "$PWD" == "$SYSTEM_REPO" ]] || die "runs only from $SYSTEM_REPO, not $PWD"
[[ "$(stat -c '%u %a' .)" == "0 755" ]] || die "$SYSTEM_REPO is not root-owned 0755"

mode="${1:-}"
[[ "$mode" == install || "$mode" == config ]] || die "usage: system-apply.sh <install|config> [--unattended]"
case "${2:-}" in
    "") ;;
    --unattended) export DOTFILES_UNATTENDED=1 ;;
    *) die "unknown argument '$2'" ;;
esac

mkdir -p "$SYSTEM_STATE"
# one system run at a time; system_copy waits on the same lock
exec 9>"$SYSTEM_STATE/lock"
flock 9

export DOTFILES="$SYSTEM_REPO" SYSTEM_STATE
FAILURES_FILE="$SYSTEM_STATE/FAILURES"
install -m644 /dev/null "$FAILURES_FILE"
fail() { echo "$1" >>"$FAILURES_FILE"; }

finished=0
DOTFILES_SECRETS=""
on_exit() {
    [[ -z "$DOTFILES_SECRETS" ]] || rm -rf "$DOTFILES_SECRETS"
    ((finished)) || exit "$EXIT_ABORTED"
}
trap on_exit EXIT

source ./scripts/lib/platform.sh
source ./scripts/lib/module.sh
source ./scripts/lib/ledger.sh
platform_load "$PWD"

system_install() {
    local pkg lsck0_snapshot
    local -a targets missing available=() nix_pkgs
    # keyring first: the pacman module's lsign needs it, a fresh bootstrap has it empty
    pacman-key --init
    pacman-key --populate archlinux
    # first boot may get here before the network is up; wsl has no networkmanager
    ! command -v nm-online >/dev/null || nm-online -q --timeout="$OFFLINE_WAIT_S" || echo "system-apply: still offline after ${OFFLINE_WAIT_S}s" >&2
    # without [lsck0] and its key every sync below would drift off the snapshot, so a failure aborts and stage.sh retries
    module_run "$PACMAN_MODULE" || { fail "$PACMAN_MODULE"; exit "$EXIT_ABORTED"; }
    # a power cut mid-transaction leaves the lock behind, and every retry boot would fail on it
    if [[ -e "$PACMAN_LOCK" ]] && ! pgrep -x pacman >/dev/null; then rm -f "$PACMAN_LOCK"; fi

    mapfile -t targets < <(platform_packages packages)
    targets+=("${EXTRA_PACKAGES[@]}")
    pacman -Syy --noconfirm
    # [lsck0] serves every listed package prebuilt; nothing is built here, gaps are only reported. pacman names every
    # target it can not resolve, by name, provide or group, before it gives up
    mapfile -t missing < <(pacman -Sp --noconfirm --print-format '%n' "${targets[@]}" 2>&1 >/dev/null \
        | sed -n 's/^error: target not found: //p')
    for pkg in "${missing[@]}"; do fail "not on the mirror: $pkg"; done
    for pkg in "${targets[@]}"; do
        [[ " ${missing[*]} " == *" $pkg "* ]] || available+=("$pkg")
    done
    echo "sources: ${#available[@]} packages in one pass, ${#missing[@]} not on the mirror" >&2
    # the one download pass: -uu moves pacstrap's packages onto the snapshot, --ask 4 replaces the old lsck0-* names
    pacman -Suu --needed --noconfirm --ask 4 "${available[@]}"

    # which lsck0 snapshot this machine runs: the pin, the db's publish time and its hash
    lsck0_snapshot="${LSCK0_SNAPSHOT:-latest} $(date -ur "$LSCK0_DB" +%FT%TZ) $(sha256sum <"$LSCK0_DB" | cut -d' ' -f1)"
    ledger_set snapshot <<<"$lsck0_snapshot"
    # after the install pass, so a dropped package only leaves once whatever replaced it is in
    ledger_packages "${targets[@]}" || fail "ledger: removing dropped packages"

    mapfile -t nix_pkgs < <(platform_packages nixpkgs)
    if ((${#nix_pkgs[@]})) && command -v nix >/dev/null 2>&1; then
        systemctl enable --now nix-daemon.socket || fail "nix-daemon.socket"
    fi

    # card access before the first config: its secrets unlock runs as the user ahead of the system layer
    module_run "$PWD/$YUBIKEY_MODULE" || fail "$YUBIKEY_MODULE"
}

system_config() {
    local script entry allowed
    # the admin's secrets: regular files by name only, each validated by its consumer, never sourced; tmpfs, gone at exit
    DOTFILES_SECRETS=$(mktemp -d /run/dotfiles-secrets.XXXXXX)
    export DOTFILES_SECRETS
    if [[ ! -t 0 ]]; then
        tar -x --no-same-owner --no-same-permissions -C "$DOTFILES_SECRETS" -f - || fail "secrets from stdin"
    fi
    allowed=" ${SYSTEM_SECRETS[*]} ${WIREGUARD} "
    for entry in "$DOTFILES_SECRETS"/* "$DOTFILES_SECRETS"/.[!.]*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        [[ -f "$entry" && ! -L "$entry" && "$allowed" == *" ${entry##*/} "* ]] || rm -rf "$entry"
    done

    # sorted path order; the pacman module ran in install
    while IFS= read -r script; do
        module_run "$script" || fail "$script"
    done < <(find "${PKG_GROUPS[@]/#/$PWD/configs/}" -type f -name system.sh -not -path "$PWD/$PACMAN_MODULE" | sort)

    # root runs nothing from a home: links left from before the root copy go
    find /usr/local/bin -maxdepth 1 -type l -lname '/home/*' -delete || fail "prune /usr/local/bin"
    ln -sfn "$SYSTEM_REPO/scripts/lib/adduser-dotfiles.sh" "$ADDUSER_LINK" || fail "$ADDUSER_LINK"
    # one-shot fixups for machine state an older config left behind; see patches/README.md
    ./scripts/lib/apply-patches.sh || fail "scripts/lib/apply-patches.sh"
    # after every system.sh and patch, so a unit is owned or dropped by what this run left enabled
    ledger_units "$PWD" || fail "ledger: disabling dropped units"
    # last, so every initramfs, cmdline and grub change of this run is rebuilt once in one order, then signed and verified
    source ./configs/hardware/boot/boot-menu/common.sh
    boot_commit || fail "boot barrier (configs/hardware/boot/boot-menu/common.sh)"
}

"system_$mode"

finished=1
if [[ -s "$FAILURES_FILE" ]]; then
    echo "=== system FAILED ===" >&2
    cat "$FAILURES_FILE" >&2
    exit "$EXIT_FAILURES"
fi
echo "system-apply: $mode done" >&2
