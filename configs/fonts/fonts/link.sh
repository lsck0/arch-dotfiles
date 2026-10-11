#!/usr/bin/env bash
# vendored OFL fonts with no arch package

dest="${HOME}/.local/share/fonts"
mkdir -p "$dest"
for f in *.ttf *.otf; do
    [ -e "$f" ] || continue
    install -m644 "$f" "$dest/$f"
done

# default family preferences + rendering
link_into "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig" fonts.conf

fc-cache -f "$dest" >/dev/null
