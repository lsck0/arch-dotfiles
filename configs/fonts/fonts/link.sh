#!/usr/bin/env bash
# vendored OFL fonts with no arch package

dest="${HOME}/.local/share/fonts"
mkdir -p "$dest"
for f in *.ttf *.otf; do
    [ -e "$f" ] || continue
    # through file_update: a person's own font under the same name is kept aside, never overwritten
    file_update "$f" "$dest/$f" || true
done

# default family preferences + rendering
link_into "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig" fonts.conf

fc-cache -f "$dest" >/dev/null
