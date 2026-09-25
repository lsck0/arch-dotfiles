#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v yazi >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.config/yazi"

ln -sfn "${PWD}/yazi.toml" "${HOME}/.config/yazi/yazi.toml"
ln -sfn "${PWD}/keymap.toml" "${HOME}/.config/yazi/keymap.toml"

# theme.toml tracks the wallust/pywal palette (rendered to ~/.cache/wal/colors-yazi.toml each switch); point yazi's theme at that file.
ln -sfn "${HOME}/.cache/wal/colors-yazi.toml" "${HOME}/.config/yazi/theme.toml"

# Seed the cache file from the current palette so yazi themes correctly before the first switch.
tpl="${PWD}/../wallust/templates/wal/colors-yazi.toml"
out="${HOME}/.cache/wal/colors-yazi.toml"
if [ ! -e "$out" ] && [ -f "$tpl" ] && [ -f "${HOME}/.cache/wal/colors" ] && [ "$(wc -l < "${HOME}/.cache/wal/colors")" -ge 16 ]; then
    mkdir -p "${HOME}/.cache/wal"
    python3 - "$tpl" "${HOME}/.cache/wal/colors" "$out" <<'PY'
import sys
tpl, colors, out = sys.argv[1], sys.argv[2], sys.argv[3]
hexes = [l.strip() for l in open(colors) if l.strip()]
s = open(tpl).read()
for i, h in enumerate(hexes[:16]):
    s = s.replace("{color%d}" % i, h)
s = s.replace("{{", "{").replace("}}", "}")
open(out, "w").write(s)
PY
fi
