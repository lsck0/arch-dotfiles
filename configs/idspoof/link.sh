#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

GROUPS_STATE="$HOME/projects/arch-dotfiles/groups.conf"
if [[ ! -f "$GROUPS_STATE" ]] || ! grep -qx pentesting "$GROUPS_STATE"; then
    exit 0
fi

if ! command -v git >/dev/null 2>&1 || ! command -v go >/dev/null 2>&1; then
    exit 0
fi

set -ex

# absolute: the build cds into the clone
BASE="$PWD"
SRC="$BASE/ID-Spoofer"

# leftover clone from an aborted run would fail the clone
rm -rf "$SRC"
trap 'rm -rf "$SRC"' EXIT

git clone https://github.com/NubleX/ID-Spoofer.git "$SRC"
cd "$SRC/idspoof"
make build
sudo cp bin/idspoof /usr/local/bin/
