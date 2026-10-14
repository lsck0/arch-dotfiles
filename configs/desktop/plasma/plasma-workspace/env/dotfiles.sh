# shellcheck shell=bash
# plasma has no uwsm: the session env hyprland shares, without env-hyprland (kwin draws decorations, reparents)
# shellcheck source=/dev/null  # resolved at login from the user's config dir
. "${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env"
