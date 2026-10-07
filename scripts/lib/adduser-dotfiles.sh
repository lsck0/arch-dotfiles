#!/usr/bin/env bash
# adduser-dotfiles <name>: a new login on this machine with its own checkout, profile and user layer; never wheel.
# linked root-owned as /usr/local/bin/adduser-dotfiles by system-apply; rerun-safe, every step skips what exists

set -euo pipefail

# bootstrap.sh's
USERNAME_PATTERN='^[a-z_][a-z0-9_-]{0,31}$'
LOGIN_SHELL=/usr/bin/zsh

die() { echo "adduser-dotfiles: $*" >&2; exit 1; }

((EUID == 0)) || exec sudo "$(readlink -f "$0")" "$@"
self=$(readlink -f "$0")
source "${self%/*}/system.sh"
[[ "$self" == "$SYSTEM_REPO/scripts/lib/adduser-dotfiles.sh" ]] || die "runs only from $SYSTEM_REPO"
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

# everything below runs as the new user, root executes nothing from the clone
[[ -e "$checkout/.git" ]] || as_user git clone "$DOTFILES_URL" "$checkout"
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
