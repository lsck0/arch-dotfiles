#!/bin/sh
# Reloads the config of every ghostty process by its own bus connection: the well-known name belongs to the single
# instance alone, and one started with --gtk-single-instance=false (the autostart window) would keep the old config.
set -eu

busctl --user --no-legend list | while read -r name _ process _; do
    case "$name $process" in
        ":"*" ghostty")
            # a window closed since the listing has no connection left to call: skip it, not fail the rest
            timeout 5 gdbus call --session --dest "$name" --object-path /com/mitchellh/ghostty \
                --method org.gtk.Actions.Activate reload-config "[]" "{}" > /dev/null || true
            ;;
    esac
done
