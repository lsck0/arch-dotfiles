#!/usr/bin/env bash
# the launcher entry: the user's spicetify copy (hook/spicetify-apply.sh) once there is one, else the stock client.
# apparmor.d's spotify profile attaches to /opt/spotify only, so the copy enters it through aa-exec (base/apparmor
# local/spotify); never unconfined while that profile is loaded, the stock client attaches by its path
copy="${XDG_DATA_HOME:-$HOME/.local/share}/spotify-patched/spotify"
if [[ -x "$copy" ]]; then
    aa-exec -p spotify -- true 2>/dev/null && exec aa-exec -p spotify -- "$copy" "$@"
    # apparmor off: nothing confines the stock client either
    [[ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" == Y ]] || exec "$copy" "$@"
fi
exec /usr/bin/spotify "$@"
