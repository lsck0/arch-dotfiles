#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# telegram lives in /usr/sbin, not always on PATH
if ! command -v Telegram >/dev/null 2>&1 && [ ! -x /usr/sbin/Telegram ]; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.cache/wal" "${HOME}/.local/share/TelegramDesktop"

# stable import path for the wallust-rendered palette
cache="${HOME}/.cache/wal/colors-telegram.tdesktop-palette"
ln -sfn "$cache" "${HOME}/.local/share/TelegramDesktop/pywal-cyberpunk.tdesktop-palette"

# seed the render so the first import works before a wallpaper switch
tpl="${PWD}/../../base/wallust/templates/wal/colors-telegram.tdesktop-palette"
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
