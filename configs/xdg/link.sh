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
