#!/usr/bin/env bash

mkdir -p "${HOME}/desktop" "${HOME}/documents" "${HOME}/downloads" "${HOME}/music" "${HOME}/pictures" "${HOME}/videos"
mkdir -p "${HOME}/sync" "${HOME}/vault"
link_into "${HOME}/.config" mimeapps.list user-dirs.conf user-dirs.dirs
# nemo also claims FileManager1 and sorts first; the user dir wins
mkdir -p "${HOME}/.local/share/dbus-1/services"
ln -sfn "${PWD}/dolphin.FileManager1.service" "${HOME}/.local/share/dbus-1/services/org.freedesktop.FileManager1.service"
# capitalized defaults xdg-user-dirs-update made before the conf above existed; rmdir keeps any with content
for dir in Desktop Documents Downloads Music Pictures Projects Public Templates Videos; do
    rmdir "${HOME}/${dir}" 2>/dev/null || true
done
# folders apps force into ~ (unreal: Library, UnrealEngine), hidden in dolphin/nemo
ln -sfn "${PWD}/home.hidden" "${HOME}/.hidden"

# a user autostart entry with Hidden=true shadows the system one of the same id
mkdir -p "${HOME}/.config/autostart"
while IFS= read -r entry; do
    entry="${entry%%#*}"
    entry="$(echo "$entry" | tr -d '[:space:]')"
    [ -n "$entry" ] || continue
    printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$entry" >"${HOME}/.config/autostart/${entry}.desktop"
done < "${PWD}/hidden-autostart.list"
# a fresh user has no applications dir yet, and update-desktop-database fails on a missing one
mkdir -p "${HOME}/.local/share/applications"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications"
fi

# portal backend preference for the Hyprland session
if command -v Hyprland >/dev/null 2>&1; then
    link_into "${HOME}/.config/xdg-desktop-portal" hyprland-portals.conf
fi

# gtk sidebar bookmarks: add the managed ones, keep whatever the user added
BOOKMARKS="${HOME}/.config/gtk-3.0/bookmarks"
mkdir -p "${HOME}/.config/gtk-3.0"
touch "$BOOKMARKS"
bookmarks=("file://${HOME}/projects Projects" "file://${HOME}/sync Syncthing")
# the nas shortcut only for a homelab user (nas/link.sh), kept out of anyone else's sidebar (and removed if a prior run added it)
if profile_has homelab; then
    bookmarks+=("file://${HOME}/nas NAS")
else
    sed -i "\#^file://${HOME}/nas\( \|\$\)#d" "$BOOKMARKS"
fi
bookmarks+=("file://${HOME}/vault Vault")
for bookmark in "${bookmarks[@]}"; do
    cut -d' ' -f1 "$BOOKMARKS" | grep -qxF "${bookmark%% *}" || echo "$bookmark" >> "$BOOKMARKS"
done

PLACES="${HOME}/.local/share/user-places.xbel"
mkdir -p "${HOME}/.local/share"
[ -f "$PLACES" ] || printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"></xbel>' > "$PLACES"
python3 - "$PLACES" "file://${HOME}" "$(profile_has homelab && echo 1 || echo 0)" <<'EOF'
import sys
import xml.etree.ElementTree as ET

path, home = sys.argv[1], sys.argv[2]
homelab = len(sys.argv) > 3 and sys.argv[3] == "1"
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
# the nas only for a homelab user, kept out of anyone else's places (and removed if a prior run added it)
if homelab:
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
# only a no longer wanted nas goes; other places are the user's
if not homelab:
    for child in list(root):
        if child.get("href") == home + "/nas":
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
tree.write(path, encoding="UTF-8", xml_declaration=True)
EOF
