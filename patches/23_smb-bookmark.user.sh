#!/usr/bin/env bash
# drop the smb://10.100.0.10 place in dolphin's sidebar an older xdg config added; the nas is mounted at ~/nas, it showed twice
set -euo pipefail

PLACES="${XDG_DATA_HOME:-$HOME/.local/share}/user-places.xbel"
NAS_URL=smb://10.100.0.10

grep -qF "href=\"$NAS_URL" "$PLACES" 2>/dev/null || exit 0
python3 - "$PLACES" "$NAS_URL" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, url = sys.argv[1], sys.argv[2]
ET.register_namespace("bookmark", "http://www.freedesktop.org/standards/desktop-bookmarks")
tree = ET.parse(path)
root = tree.getroot()
for child in list(root):
    if child.get("href", "").startswith(url):
        root.remove(child)
tree.write(path, encoding="UTF-8", xml_declaration=True)
PY
