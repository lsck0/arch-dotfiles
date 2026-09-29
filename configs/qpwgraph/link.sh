#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v qpwgraph >/dev/null 2>&1; then
    exit 0
fi

set -ex

# Empty scaffold: save a patchbay layout as session.qpwgraph in this dir.
# No autostart by choice; launch qpwgraph manually or wire it up yourself later.
: