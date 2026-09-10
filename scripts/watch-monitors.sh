#!/usr/bin/env bash
# awww-daemon only paints outputs it already knew about at the moment the
# wallpaper was last set, so a monitor plugged in afterwards stays blank.
# This listens on Hyprland's event socket and reruns switch-wallpaper.sh with
# the last-used wallpaper whenever a new output shows up.

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SOCKET="$RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$SOCKET" | while IFS= read -r line; do
    case "$line" in
    monitoradded*)
        wallpaper=$(readlink -f "$HOME/.cache/wal/wallpaper" 2>/dev/null)
        if [[ -n "$wallpaper" && -f "$wallpaper" ]]; then
            # give Hyprland a moment to finish placing the new output first
            sleep 1
            "$HOME/projects/arch-dotfiles/scripts/switch-wallpaper.sh" "$wallpaper"
        fi
        ;;
    esac
done
