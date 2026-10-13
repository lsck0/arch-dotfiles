#!/usr/bin/env bash

mkdir -p "${HOME}/desktop" "${HOME}/documents" "${HOME}/downloads" "${HOME}/music" "${HOME}/pictures" "${HOME}/videos"
mkdir -p "${HOME}/sync" "${HOME}/vault"
link_into "${HOME}/.config" mimeapps.list user-dirs.conf user-dirs.dirs
# nemo also claims FileManager1 and sorts first; the user dir wins
link_as "${PWD}/dolphin.FileManager1.service" "${HOME}/.local/share/dbus-1/services/org.freedesktop.FileManager1.service"
# capitalized defaults xdg-user-dirs-update made before the conf above existed; rmdir keeps any with content
for dir in Desktop Documents Downloads Music Pictures Projects Public Templates Videos; do
    rmdir "${HOME}/${dir}" 2>/dev/null || true
done
# folders apps force into ~ (unreal: Library, UnrealEngine), hidden in dolphin/nemo
link_as "${PWD}/home.hidden" "${HOME}/.hidden"

# a user autostart entry with Hidden=true shadows the system one of the same id
mkdir -p "${HOME}/.config/autostart"
while IFS= read -r entry; do
    entry="${entry%%#*}"
    entry="$(echo "$entry" | tr -d '[:space:]')"
    [ -n "$entry" ] || continue
    # through file_update: a person's own entry of that id is preserved, not overwritten
    tmp=$(mktemp)
    printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$entry" >"$tmp"
    file_update "$tmp" "${HOME}/.config/autostart/${entry}.desktop" || true
    rm -f "$tmp"
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

# sidebar order, dolphin and gtk/nemo alike: Home, the XDG folders sorted, Vault, Sync, NAS, Trash.
# gtk renders Home, the XDG dirs and Trash natively, so nemo's bookmarks file carries only Vault/Sync/NAS.
nas=$(profile_has homelab && echo 1 || echo 0)

BOOKMARKS="${HOME}/.config/gtk-3.0/bookmarks"
mkdir -p "${HOME}/.config/gtk-3.0"
# bookmarks added by hand in nemo make it differ from the last write: file_update preserves that copy first
tmp=$(mktemp)
{
    echo "file://${HOME}/vault Vault"
    echo "file://${HOME}/sync Sync"
    [ "$nas" = 1 ] && echo "file://${HOME}/nas NAS"
} >"$tmp"
file_update "$tmp" "$BOOKMARKS" || true
rm -f "$tmp"

# dolphin places: authoritative, full ordered list (dolphin keeps its own Devices/Network sections separately)
PLACES="${HOME}/.local/share/user-places.xbel"
mkdir -p "${HOME}/.local/share"
python3 - "$PLACES" "file://${HOME}" "$nas" <<'EOF'
import sys
import xml.etree.ElementTree as ET

path, home, nas = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
ns = "http://www.freedesktop.org/standards/desktop-bookmarks"
ET.register_namespace("bookmark", ns)

places = [
    (home, "Home", "user-home"),
    (home + "/desktop", "Desktop", "user-desktop"),
    (home + "/documents", "Documents", "folder-documents"),
    (home + "/downloads", "Downloads", "folder-downloads"),
    (home + "/music", "Music", "folder-music"),
    (home + "/pictures", "Pictures", "folder-pictures"),
    (home + "/videos", "Videos", "folder-videos"),
    (home + "/vault", "Vault", "folder-locked"),
    (home + "/sync", "Sync", "folder-sync"),
]
if nas:
    places.append((home + "/nas", "NAS", "folder-network"))
places.append(("trash:/", "Trash", "user-trash"))

root = ET.Element("xbel")
for href, title, icon in places:
    bookmark = ET.SubElement(root, "bookmark", href=href)
    ET.SubElement(bookmark, "title").text = title
    info = ET.SubElement(bookmark, "info")
    ET.SubElement(ET.SubElement(info, "metadata", owner="http://freedesktop.org"), "{%s}icon" % ns, name=icon)
    ET.SubElement(ET.SubElement(info, "metadata", owner="http://www.kde.org"), "isSystemItem").text = "true"
ET.ElementTree(root).write(path, encoding="UTF-8", xml_declaration=True)
EOF
