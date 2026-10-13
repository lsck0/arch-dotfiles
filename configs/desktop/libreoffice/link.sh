#!/usr/bin/env bash

# libreoffice follows the gtk theme (oomox, regenerated from the wallpaper); a stored appearance or libreoffice theme
# override paints its dialogs in its own light palette instead, so both go back to their default of following the system
XCU="${HOME}/.config/libreoffice/4/user/registrymodifications.xcu"
[[ -f "$XCU" ]] || exit 0
# it rewrites the file on exit, an edit under a running instance would be lost
pgrep -x soffice.bin >/dev/null && { echo "libreoffice: running, appearance reset skipped" >&2; exit 0; }
sed -i -E '/oor:path="\/org.openoffice.Office.Common\/Appearance"><prop oor:name="(ApplicationAppearance|LibreOfficeTheme)"/d' "$XCU"
