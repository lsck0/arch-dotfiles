#!/usr/bin/env bash
# Build + install unreal-engine-bin (AUR) from the Epic-login-gated zip, downloaded by hand from
# https://www.unrealengine.com/linux into ~/sync. A newer zip than the AUR pkgver is used as-is.

set -euo pipefail

AUR_URL="https://aur.archlinux.org/unreal-engine-bin.git"
SYNC_DIR="${HOME}/sync"
# on disk, not /tmp: unpacked engine is ~60 GB and /tmp is tmpfs
BUILD_DIR="${HOME}/.cache/unreal-engine-bin"

if pacman -Q unreal-engine-bin >/dev/null 2>&1; then
    echo "unreal-engine-bin already installed"
    exit 0
fi

zip_path=$(find "$SYNC_DIR" -maxdepth 1 -name 'Linux_Unreal_Engine_*.zip' | sort -V | tail -n 1)
if [[ -z "$zip_path" ]]; then
    echo "no Linux_Unreal_Engine_*.zip in ${SYNC_DIR}, download it from https://www.unrealengine.com/linux" >&2
    exit 1
fi
zip_version=$(basename "$zip_path" .zip)
zip_version=${zip_version#Linux_Unreal_Engine_}

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

ln -s "$zip_path" "Linux_Unreal_Engine_${zip_version}.zip"
# uncompressed package: zstd over ~60 GB of engine takes longer than the install is worth
PKGEXT=.pkg.tar makepkg -si --noconfirm
