#!/usr/bin/env bash

set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
    exit 0
fi

COMPAT_DIR="$HOME/.steam/root/compatibilitytools.d"
OVERLAY_URL="https://github.com/thaylorz/proton-ge-custom/releases/download/proton-layered-overlay-v1/Proton-LayeredOverlay.tar.gz"

mkdir -p "$COMPAT_DIR"

install_proton_ge() {
    local api="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
    local tag asset url sum_url tmp

    tag=$(curl -fsSL "$api" | jq -r '.tag_name')
    asset="${tag}-x86_64"

    # Upstream tarballs unpack to <tag>-x86_64, not <tag>.
    if [ -d "$COMPAT_DIR/$asset" ]; then
        return
    fi

    url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${tag}/${asset}.tar.gz"
    sum_url="${url%.tar.gz}.sha512sum"

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN

    curl -fL --progress-bar -o "$tmp/$asset.tar.gz" "$url"
    curl -fsSL -o "$tmp/$asset.sha512sum" "$sum_url"

    (cd "$tmp" && sha512sum -c "$asset.sha512sum")

    tar -xzf "$tmp/$asset.tar.gz" -C "$COMPAT_DIR"
}

install_overlay() {
    local tmp

    if [ -d "$COMPAT_DIR/Proton-LayeredOverlay" ]; then
        return
    fi

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN

    curl -fL --progress-bar -o "$tmp/overlay.tar.gz" "$OVERLAY_URL"
    tar -xzf "$tmp/overlay.tar.gz" -C "$COMPAT_DIR"
}

install_proton_ge
install_overlay
