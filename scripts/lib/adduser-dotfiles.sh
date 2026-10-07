#!/usr/bin/env bash
# adduser-dotfiles <name>: a new login on this machine with its own checkout, profile and user layer; never wheel.
# linked root-owned as /usr/local/bin/adduser-dotfiles by system-apply; rerun-safe, every step skips what exists

set -euo pipefail

# bootstrap.sh's
USERNAME_PATTERN='^[a-z_][a-z0-9_-]{0,31}$'
LOGIN_SHELL=/usr/bin/zsh
SIGNING_KEY_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
SIGNING_KEY_FILE=configs/base/gnupg/luca-sandrock.pub.asc
# system.sh's SYSTEM_REPO, checked before any file of it is sourced
SELF=/var/lib/dotfiles/repo/scripts/lib/adduser-dotfiles.sh

die() { echo "adduser-dotfiles: $*" >&2; exit 1; }

# the root copy, whatever path it was called by: root never runs a file a user can write
((EUID == 0)) || exec sudo "$SELF" "$@"
[[ "$(readlink -f "$0")" == "$SELF" ]] || die "runs only as $SELF"
source "${SELF%/*}/system.sh"
(($# == 1)) || die "usage: adduser-dotfiles <name>"
name="$1"
[[ "$name" =~ $USERNAME_PATTERN ]] || die "invalid name '$name', expected $USERNAME_PATTERN"

id -u "$name" >/dev/null 2>&1 || useradd -m -s "$LOGIN_SHELL" "$name"
# a rerun after a failed or skipped passwd asks again
[[ "$(passwd -S "$name" | cut -d' ' -f2)" == P ]] || passwd "$name"

home=$(getent passwd "$name" | cut -d: -f6)
checkout="$home/projects/arch-dotfiles"
profile="$home/.config/dotfiles/profile.sh"
as_user() { runuser -u "$name" -- "$@"; }

# clone_verify: bootstrap.sh's check, the fresh clone's HEAD signed by SIGNING_KEY_FINGERPRINT, the key from the root copy
clone_verify() {
    local gnupg_home status signer verified=0
    gnupg_home=$(as_user mktemp -d)
    as_user env GNUPGHOME="$gnupg_home" gpg --batch --quiet --import "$SYSTEM_REPO/$SIGNING_KEY_FILE" || return 1
    status=$(as_user env GNUPGHOME="$gnupg_home" git -C "$checkout" verify-commit --raw HEAD 2>&1) && verified=1
    as_user env GNUPGHOME="$gnupg_home" gpgconf --kill all
    rm -rf "$gnupg_home"
    # gpg status line: VALIDSIG <signing key> ... <primary key>, field 12 counting the [GNUPG:] prefix
    signer=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {print $12}' <<<"$status")
    ((verified)) && [[ "$signer" == "$SIGNING_KEY_FINGERPRINT" ]]
}

# everything below runs as the new user, root executes nothing from the clone; an unverified clone is not kept for a rerun
if [[ ! -e "$checkout/.git" ]]; then
    as_user git clone "$DOTFILES_URL" "$checkout"
    clone_verify || { rm -rf "$checkout"; die "$DOTFILES_URL HEAD is not signed by $SIGNING_KEY_FINGERPRINT, refusing it"; }
fi
if [[ -f "$checkout/profiles/$name.sh" && ! -e "$profile" ]]; then
    as_user install -Dm644 "$checkout/profiles/$name.sh" "$profile"
fi
# the fresh checkout already describes this user, so none of its user patches apply
if [[ ! -e "$home/.local/state/dotfiles/patches-applied" ]]; then
    as_user env DOTFILES="$checkout" "$checkout/scripts/lib/apply-patches.sh" --mark-applied
fi

# a login session, so user units and the bus work like after a real login
systemd-run --quiet --wait --pipe --collect --uid="$name" -p PAMName=login -p WorkingDirectory="$checkout" \
    bash -c './install.sh --user && ./config.sh --user'
