#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh

set -e

mkdir -p "${HOME}/desktop" "${HOME}/documents" "${HOME}/downloads" "${HOME}/music" "${HOME}/pictures" "${HOME}/videos"
mkdir -p "${HOME}/sync" "${HOME}/vault"
ln -sfn "${PWD}/mimeapps.list" "${HOME}/.config/mimeapps.list"
ln -sfn "${PWD}/user-dirs.conf" "${HOME}/.config/user-dirs.conf"
ln -sfn "${PWD}/user-dirs.dirs" "${HOME}/.config/user-dirs.dirs"
# capitalized defaults xdg-user-dirs-update made before the conf above existed; rmdir keeps any with content
for dir in Desktop Documents Downloads Music Pictures Projects Public Templates Videos; do
    rmdir "${HOME}/${dir}" 2>/dev/null || true
done
# folders apps force into ~ (unreal: Library, UnrealEngine), hidden in dolphin/nemo
ln -sfn "${PWD}/home.hidden" "${HOME}/.hidden"

mkdir -p "${HOME}/.local/share/applications"
while IFS= read -r entry; do
    entry="${entry%%#*}"
    entry="$(echo "$entry" | tr -d '[:space:]')"
    [ -n "$entry" ] || continue
    cat > "${HOME}/.local/share/applications/${entry}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${entry}
Exec=true
NoDisplay=true
Hidden=true
EOF
done < "${PWD}/hidden-apps.list"
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true

# portal backend preference for the Hyprland session
if command -v Hyprland >/dev/null 2>&1; then
    mkdir -p "${HOME}/.config/xdg-desktop-portal"
    ln -sfn "${PWD}/hyprland-portals.conf" "${HOME}/.config/xdg-desktop-portal/hyprland-portals.conf"
fi

# gtk sidebar bookmarks, owned whole so stale entries do not linger
mkdir -p "${HOME}/.config/gtk-3.0"
{
    echo "file://${HOME}/projects Projects"
    echo "file://${HOME}/sync Syncthing"
    # homelab nas topology is luca-only, kept out of a guest's sidebar
    is_personal && echo "file://${HOME}/nas NAS"
    echo "file://${HOME}/vault Vault"
} > "${HOME}/.config/gtk-3.0/bookmarks"

PLACES="${HOME}/.local/share/user-places.xbel"
mkdir -p "${HOME}/.local/share"
[ -f "$PLACES" ] || printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"></xbel>' > "$PLACES"
python3 - "$PLACES" "file://${HOME}" "$(is_personal && echo 1 || echo 0)" <<'EOF'
import sys
import xml.etree.ElementTree as ET

path, home = sys.argv[1], sys.argv[2]
personal = len(sys.argv) > 3 and sys.argv[3] == "1"
ns = "http://www.freedesktop.org/standards/desktop-bookmarks"
ET.register_namespace("bookmark", ns)
tree = ET.parse(path)
root = tree.getroot()

# dolphin only seeds defaults into an empty file
places = [
    (home, "Home", "user-home", True),
    (home + "/projects", "Projects", "folder-development", False),
    (home + "/sync", "Syncthing", "folder-sync", False),
]
# homelab nas topology is luca-only, kept out of a guest's places (and removed if a prior run added it)
if personal:
    places.append((home + "/nas", "NAS", "folder-network", False))
places += [
    (home + "/vault", "Vault", "folder-locked", False),
    (home + "/desktop", "Desktop", "user-desktop", True),
    (home + "/documents", "Documents", "folder-documents", True),
    (home + "/downloads", "Downloads", "folder-downloads", True),
    (home + "/music", "Music", "folder-music", True),
    (home + "/pictures", "Pictures", "folder-pictures", True),
    (home + "/videos", "Videos", "folder-videos", True),
    ("remote:/", "Network", "folder-network", True),
    ("trash:/", "Trash", "user-trash", True),
]
# the list above owns every file:// bookmark
managed = {href for href, _, _, _ in places}
for child in list(root):
    if child.get("href", "").startswith("file://") and child.get("href") not in managed:
        root.remove(child)
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
# the nas is mounted locally now, a leftover smb bookmark would duplicate it
for child in list(root):
    if child.get("href", "").startswith("smb://10.100.0.10"):
        root.remove(child)
tree.write(path, encoding="UTF-8", xml_declaration=True)
EOF
