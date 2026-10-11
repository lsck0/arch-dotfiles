#!/usr/bin/env bash
# the launcher entry: the user's spicetify copy (hook/spicetify-apply.sh) once there is one, else the stock client
copy="${XDG_DATA_HOME:-$HOME/.local/share}/spotify-patched/spotify"
[[ -x "$copy" ]] && exec "$copy" "$@"
exec /usr/bin/spotify "$@"
