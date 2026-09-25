#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# Telegram lives in /usr/sbin, which is not always on PATH; accept either.
if ! command -v Telegram >/dev/null 2>&1 && [ ! -x /usr/sbin/Telegram ]; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.cache/wal" "${HOME}/.local/share/TelegramDesktop"

# Palette tracks the wallust/pywal palette (rendered to ~/.cache/wal/colors-telegram.tdesktop-palette each switch); expose a stable import path.
cache="${HOME}/.cache/wal/colors-telegram.tdesktop-palette"
ln -sfn "$cache" "${HOME}/.local/share/TelegramDesktop/pywal-cyberpunk.tdesktop-palette"

# Seed the cache file from the current palette so a first import works before the first switch.
tpl="${PWD}/../wallust/templates/wal/colors-telegram.tdesktop-palette"
if [ ! -e "$cache" ] && [ -f "$tpl" ] && [ -f "${HOME}/.cache/wal/colors.sh" ]; then
    python3 - "$tpl" "${HOME}/.cache/wal/colors.sh" "$cache" <<'PY'
import re, sys
tpl, colorsh, out = sys.argv[1], sys.argv[2], sys.argv[3]
vals = {}
for line in open(colorsh):
    m = re.match(r"(\w+)='(#[0-9a-fA-F]{6})'", line.strip())
    if m:
        vals[m.group(1)] = m.group(2)
s = open(tpl).read()
for k, v in vals.items():
    s = s.replace("{%s}" % k, v)
open(out, "w").write(s)
PY
fi
