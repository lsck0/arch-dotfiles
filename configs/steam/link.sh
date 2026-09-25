#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v steam >/dev/null 2>&1; then
    exit 0
fi

set -ex

skins="${HOME}/.local/share/Steam/millennium/themes"
theme="${skins}/cyberpunk"

mkdir -p "${theme}"

# Symlink theme files into Steam's Millennium skins dir; the repo stays the source.
ln -sfn "${PWD}/themes/cyberpunk/skin.json" "${theme}/skin.json"
ln -sfn "${PWD}/themes/cyberpunk/shared.css" "${theme}/shared.css"
ln -sfn "${PWD}/themes/cyberpunk/libraryroot.custom.css" "${theme}/libraryroot.custom.css"
ln -sfn "${PWD}/themes/cyberpunk/friends.custom.css" "${theme}/friends.custom.css"
ln -sfn "${PWD}/themes/cyberpunk/bigpicture.custom.css" "${theme}/bigpicture.custom.css"

# colors.css tracks the wallust/pywal palette (rendered to ~/.cache/wal/colors-steam.css each switch); the custom CSS @imports this symlink.
ln -sfn "${HOME}/.cache/wal/colors-steam.css" "${theme}/colors.css"

# Seed the cache file from the current palette so the theme colors before the first switch.
tpl="${PWD}/../wallust/templates/wal/colors-steam.css"
out="${HOME}/.cache/wal/colors-steam.css"
if [ ! -e "$out" ] && [ -f "$tpl" ] && [ -f "${HOME}/.cache/wal/colors" ] && [ "$(wc -l < "${HOME}/.cache/wal/colors")" -ge 16 ]; then
    mkdir -p "${HOME}/.cache/wal"
    python3 - "$tpl" "${HOME}/.cache/wal/colors" "$out" <<'PY'
import sys
tpl, colors, out = sys.argv[1], sys.argv[2], sys.argv[3]
hexes = [l.strip() for l in open(colors) if l.strip()]
s = open(tpl).read()
for i, h in enumerate(hexes[:16]):
    s = s.replace("{color%d}" % i, h)
s = s.replace("{background}", hexes[0])
s = s.replace("{foreground}", hexes[15] if len(hexes) > 15 else hexes[-1])
s = s.replace("{{", "{").replace("}}", "}")
open(out, "w").write(s)
PY
fi

# Select the theme in Millennium's config if it has initialized (close Steam first so it is not overwritten on exit).
cfg="${HOME}/.config/millennium/config.json"
if [ -f "$cfg" ]; then
    python3 - "$cfg" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.setdefault("themes", {})["activeTheme"] = "cyberpunk"
json.dump(d, open(p, "w"), indent=2)
PY
fi
