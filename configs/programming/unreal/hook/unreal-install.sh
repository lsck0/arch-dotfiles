#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# the engine from the newest ~/sync zip (Epic-login-gated, synced from where it was downloaded), into the home like jai:
# part of the dotfiles, so never asked and never root. no-op unless the zip is new; link.sh reruns it for later versions

set -euo pipefail
source "$DOTFILES/scripts/lib/user-hook.sh"

SYNC_DIR="${HOME}/sync"
DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}"
ENGINE="${DATA_DIR}/unreal-engine"
STAMP="${ENGINE}/.installed-from"
EDITOR_LINK="${HOME}/.local/bin/unreal-editor"
DESKTOP_FILE="${DATA_DIR}/applications/unreal-engine.desktop"

zip_path=$(find "$SYNC_DIR" -maxdepth 1 -name 'Linux_Unreal_Engine_*.zip' 2>/dev/null | sort -V | tail -n 1)
if [[ -z "$zip_path" ]]; then
    exit 0
fi
zip_name=$(basename "$zip_path")
zip_version=${zip_name%.zip}
zip_version=${zip_version#Linux_Unreal_Engine_}
# config.sh and the path unit both run this: the second waits, then finds the stamp the first wrote
mkdir -p "$DATA_DIR"
exec 9>"${ENGINE}.lock"
flock 9
if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$zip_name" ]]; then
    user_hook_retire unreal-install
    exit 0
fi

# unpacked next to the engine, not in /tmp: ~60 GB, and /tmp is tmpfs; the old engine only goes once the new one is whole
staging="${ENGINE}.new"
rm -rf "$staging"
mkdir -p "$staging"
trap 'rm -rf "$staging"' EXIT
unzip -q "$zip_path" -d "$staging"
# the zip holds Engine/ either at its top or under one folder
root=$(find "$staging" -maxdepth 2 -type d -name Engine -printf '%h\n' -quit)
[[ -n "$root" && -x "${root}/Engine/Binaries/Linux/UnrealEditor" ]] || {
    echo "unreal: no Engine/Binaries/Linux/UnrealEditor in ${zip_name}" >&2
    exit 1
}
echo "$zip_name" >"${root}/.installed-from"
rm -rf "$ENGINE"
mv "$root" "$ENGINE"

mkdir -p "$(dirname "$EDITOR_LINK")" "$(dirname "$DESKTOP_FILE")"
ln -sfn "${ENGINE}/Engine/Binaries/Linux/UnrealEditor" "$EDITOR_LINK"
icon=$(find "${ENGINE}/Engine/Source/Programs/UnrealVersionSelector" -name 'Icon.png' 2>/dev/null | head -n 1 || true)
cat >"$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Unreal Engine
Comment=Unreal Editor ${zip_version}
Exec=${ENGINE}/Engine/Binaries/Linux/UnrealEditor %U
${icon:+Icon=${icon}}
Terminal=false
Categories=Development;IDE;
StartupWMClass=UnrealEditor
DESKTOP
command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESKTOP_FILE")" || true

# bridge and fab from ~/sync go into the engine, which is the user's own now
"$DOTFILES/configs/programming/unreal/unreal-install-plugins.sh" \
    || echo "unreal: plugins not installed, rerun unreal-install-plugins" >&2
notify-send -a Unreal "Unreal Engine" "Installed ${zip_version}" 2>/dev/null || true
user_hook_retire unreal-install
