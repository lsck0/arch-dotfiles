#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v mount.cifs >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo mkdir -p /mnt/homelab
sudo cp ${PWD}/mnt-homelab.mount /etc/systemd/system/
sudo cp ${PWD}/mnt-homelab.automount /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mnt-homelab.automount

# add NAS to nemo/nautilus sidebar bookmarks
mkdir -p "${HOME}/.config/gtk-3.0"
BOOKMARK="${HOME}/.config/gtk-3.0/bookmarks"
grep -qxF "smb://10.100.0.108/homelab Homelab" "$BOOKMARK" 2>/dev/null \
  || echo "smb://10.100.0.108/homelab Homelab" >> "$BOOKMARK"

# add NAS to Dolphin's Places panel (KDE reads its own xbel file, not the GTK bookmarks above)
if command -v dolphin >/dev/null 2>&1; then
    mkdir -p "${HOME}/.local/share"
    PLACES="${HOME}/.local/share/user-places.xbel"
    if [ ! -f "$PLACES" ]; then
        cat > "$PLACES" <<-'EOF'
			<?xml version="1.0" encoding="UTF-8"?>
			<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:kdepriv="http://www.kde.org/kdepriv" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">
			</xbel>
		EOF
    fi
    if ! grep -q 'smb://10.100.0.108/homelab' "$PLACES"; then
        python3 - "$PLACES" <<-'EOF'
			import sys
			import xml.etree.ElementTree as ET

			path = sys.argv[1]
			tree = ET.parse(path)
			root = tree.getroot()

			bookmark = ET.SubElement(root, "bookmark", href="smb://10.100.0.108/homelab")
			title = ET.SubElement(bookmark, "title")
			title.text = "Homelab"
			info = ET.SubElement(bookmark, "info")
			metadata = ET.SubElement(info, "metadata", owner="http://freedesktop.org")
			ET.SubElement(metadata, "{http://www.freedesktop.org/standards/desktop-bookmarks}icon", name="folder-network")

			tree.write(path, encoding="UTF-8", xml_declaration=True)
		EOF
    fi
fi
