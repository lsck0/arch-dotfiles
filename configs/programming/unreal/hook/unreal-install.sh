#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# unreal-engine-bin from the newest ~/sync zip (Epic-login-gated, synced from where it was downloaded); runs on every ~/sync change

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/$DOTFILES/scripts/lib/user-hook.sh"

AUR_URL="https://aur.archlinux.org/unreal-engine-bin.git"
SYNC_DIR="${HOME}/sync"
# on disk, not /tmp: unpacked engine is ~60 GB and /tmp is tmpfs
BUILD_DIR="${HOME}/.cache/unreal-engine-bin"
# zip version the user chose to skip, so later ~/sync changes stop asking
SKIP_STAMP="${XDG_STATE_HOME:-${HOME}/.local/state}/unreal-install.skipped"

if pacman -Q unreal-engine-bin >/dev/null 2>&1; then
    echo "unreal-engine-bin already installed"
    user_hook_retire unreal-install
    exit 0
fi

zip_path=$(find "$SYNC_DIR" -maxdepth 1 -name 'Linux_Unreal_Engine_*.zip' | sort -V | tail -n 1)
if [[ -z "$zip_path" ]]; then
    exit 0
fi
zip_version=$(basename "$zip_path" .zip)
zip_version=${zip_version#Linux_Unreal_Engine_}

# no terminal means the path unit: ask first, else the install's sudo lights the fingerprint reader at every login
if [[ ! -t 0 ]]; then
    if [[ -f "$SKIP_STAMP" && "$(cat "$SKIP_STAMP")" == "$zip_version" ]]; then
        exit 0
    fi
    # -t 0: the default expiry closes it in seconds, which reads as dismissed
    answer=$(notify-send -a Unreal -t 0 --wait -A install=Install -A skip="Skip ${zip_version}" \
        "Unreal Engine" "Install ${zip_version} from ~/sync? The install asks for the YubiKey or fingerprint." \
        2>/dev/null || true)
    echo "notification answer: ${answer:-dismissed}"
    case "$answer" in
    install) ;;
    skip)
        mkdir -p "$(dirname "$SKIP_STAMP")"
        echo "$zip_version" >"$SKIP_STAMP"
        exit 0
        ;;
    # dismissed or expired: ask again on the next ~/sync change
    *) exit 0 ;;
    esac
fi

rm -rf "$BUILD_DIR"
git clone --depth 1 "$AUR_URL" "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT
cd "$BUILD_DIR"

aur_version=$(sed -n 's/^pkgver=//p' PKGBUILD)
if [[ "$zip_version" != "$aur_version" ]]; then
    # the zip is the first source, so its checksum is the first sha256sums entry
    echo "AUR pkgver ${aur_version} != zip ${zip_version}: bumping pkgver and pinning the zip's own sha256" >&2
    zip_sha=$(sha256sum "$zip_path" | cut -d ' ' -f 1)
    sed -i -e "s/^pkgver=.*/pkgver=${zip_version}/" -e "s/^sha256sums=('[0-9a-f]*'/sha256sums=('${zip_sha}'/" PKGBUILD
fi

# makepkg.conf's debug option copies the sources of every engine binary into a -debug package, minutes of work for nothing
sed -i 's/^options=(/options=(!debug /' PKGBUILD

ln -s "$zip_path" "Linux_Unreal_Engine_${zip_version}.zip"
# uncompressed package: zstd over ~60 GB of engine takes longer than the install is worth
export PKGEXT=.pkg.tar
# no makedepends, so build without the deps check and its sudo; pacman -U pulls the runtime deps from the repos
makepkg --nodeps --noconfirm
# the only sudo, right after the build: YubiKey touch (pam_u2f) or fingerprint; a miss fails and asks again next change
notify-send -a Unreal "Unreal Engine" "Touch the YubiKey or fingerprint reader to install ${zip_version}" 2>/dev/null || true
mapfile -t packages < <(makepkg --packagelist)
sudo pacman -U --noconfirm "${packages[@]}"
user_hook_retire unreal-install
