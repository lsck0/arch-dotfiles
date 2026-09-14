#!/usr/bin/env bash

if ! command -v task >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ~/.task/hooks
mkdir -p ~/.timewarrior

HOOK=/usr/share/doc/timew/ext/on-modify.timewarrior
if [[ -f "$HOOK" ]]; then
    install -m755 "$HOOK" ~/.task/hooks/on-modify.timewarrior
else
    echo "task: $HOOK not found (timew not installed), skipping hook" >&2
fi
