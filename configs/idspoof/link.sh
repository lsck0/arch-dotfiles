#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v git >/dev/null 2>&1 || ! command -v go >/dev/null 2>&1; then
    exit 0
fi

set -ex

# Absolute, because the build below cds into the clone: the old `cd ..` landed
# in ID-Spoofer/ rather than back here, so `rm -rf ID-Spoofer` deleted nothing
# and the clone was left sitting inside the dotfiles repo after every install.
BASE="$PWD"
SRC="$BASE/ID-Spoofer"

# A leftover clone from an aborted earlier run would make `git clone` fail, and
# `set -e` would take the whole script down with it.
rm -rf "$SRC"
trap 'rm -rf "$SRC"' EXIT

git clone https://github.com/NubleX/ID-Spoofer.git "$SRC"
cd "$SRC/idspoof"
make build
sudo cp bin/idspoof /usr/local/bin/
