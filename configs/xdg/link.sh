#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

mkdir -p ${HOME}/desktop ${HOME}/documents ${HOME}/downloads ${HOME}/music ${HOME}/pictures ${HOME}/videos ${HOME}/projects
ln -sfn ${PWD}/mimeapps.list ${HOME}/.config/mimeapps.list
ln -sfn ${PWD}/user-dirs.dirs ${HOME}/.config/user-dirs.dirs

# custom folder icon for ~/projects (no XDG standard icon exists for it, unlike Desktop/Pictures/etc.)
# .directory covers Dolphin/KDE; gio metadata covers Nemo/GTK, which ignores .directory Icon=
cat > ${HOME}/projects/.directory <<'EOF'
[Desktop Entry]
Icon=folder-development
EOF
command -v gio >/dev/null 2>&1 && gio set ${HOME}/projects metadata::custom-icon-name folder-development || true

# portal backend preference for the Hyprland session
if command -v Hyprland >/dev/null 2>&1; then
    mkdir -p ${HOME}/.config/xdg-desktop-portal
    ln -sfn ${PWD}/hyprland-portals.conf ${HOME}/.config/xdg-desktop-portal/hyprland-portals.conf
fi

# ~/projects in the file manager sidebars: GTK bookmarks for Nemo, user-places.xbel for Dolphin
mkdir -p ${HOME}/.config/gtk-3.0
grep -qxF "file://${HOME}/projects Projects" ${HOME}/.config/gtk-3.0/bookmarks 2>/dev/null \
    || echo "file://${HOME}/projects Projects" >> ${HOME}/.config/gtk-3.0/bookmarks

PLACES="${HOME}/.local/share/user-places.xbel"
mkdir -p ${HOME}/.local/share
[ -f "$PLACES" ] || printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"></xbel>' > "$PLACES"
python3 - "$PLACES" "file://${HOME}" <<'EOF'
import sys
import xml.etree.ElementTree as ET

path, home = sys.argv[1], sys.argv[2]
ns = "http://www.freedesktop.org/standards/desktop-bookmarks"
ET.register_namespace("bookmark", ns)
tree = ET.parse(path)
root = tree.getroot()

# Dolphin only seeds its defaults into an empty file, and nas/link.sh may already
# have added a bookmark, so the standard places are ensured here as well.
places = [
    (home, "Home", "user-home", True),
    (home + "/projects", "Projects", "folder-development", False),
    (home + "/desktop", "Desktop", "user-desktop", True),
    (home + "/documents", "Documents", "folder-documents", True),
    (home + "/downloads", "Downloads", "folder-downloads", True),
    (home + "/music", "Music", "folder-music", True),
    (home + "/pictures", "Pictures", "folder-pictures", True),
    (home + "/videos", "Videos", "folder-videos", True),
    ("remote:/", "Network", "folder-network", True),
    ("trash:/", "Trash", "user-trash", True),
]
position = 0
for href, title, icon, system in places:
    children = list(root)
    found = next((i for i, child in enumerate(children) if child.get("href") == href), None)
    if found is not None:
        position = found + 1
        continue
    bookmark = ET.Element("bookmark", href=href)
    ET.SubElement(bookmark, "title").text = title
    info = ET.SubElement(bookmark, "info")
    ET.SubElement(ET.SubElement(info, "metadata", owner="http://freedesktop.org"), "{%s}icon" % ns, name=icon)
    if system:
        ET.SubElement(ET.SubElement(info, "metadata", owner="http://www.kde.org"), "isSystemItem").text = "true"
    root.insert(position, bookmark)
    position += 1
tree.write(path, encoding="UTF-8", xml_declaration=True)
EOF
