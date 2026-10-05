#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ../../scripts/lib/fetch.sh

if ! command -v curl >/dev/null 2>&1; then
    echo "protonup: curl missing, skipping" >&2
    exit 0
fi

COMPAT_DIR="$HOME/.steam/root/compatibilitytools.d"
OVERLAY_URL="https://github.com/thaylorz/proton-ge-custom/releases/download/proton-layered-overlay-v1/Proton-LayeredOverlay.tar.gz"
# the release ships no checksum and a tag can be re-uploaded, so the archive is pinned by content
OVERLAY_SHA256=ba515bf1fa6e7f9634cb894640f21f0359dc7435c3a5ce458a37087ed6c3a4d7
# proton-ge runs as part of every game, so it is pinned to a version and a repo-held sha256 instead of
# fetching the latest tag and its upstream checksum from the same release (that checksum is pure tofu);
# bump by updating both constants from the GloriousEggroll release the sha was computed against
PROTON_GE_VERSION=GE-Proton11-7
PROTON_GE_SHA256=c5448b76a230384e2d7bc6beb5ccb97bafb7e2c3b6c527cb03a1a546bbcb00a0

mkdir -p "$COMPAT_DIR"

install_proton_ge() {
    local asset="${PROTON_GE_VERSION}-x86_64" url tmp

    # tarballs unpack to <version>-x86_64
    if [ -d "$COMPAT_DIR/$asset" ]; then
        return
    fi

    url="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_GE_VERSION}/${asset}.tar.gz"

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"; trap - RETURN' RETURN

    fetch_pinned "$url" "$PROTON_GE_SHA256" "$tmp/$asset.tar.gz"
    tar -xzf "$tmp/$asset.tar.gz" -C "$COMPAT_DIR"
}

install_overlay() {
    local tmp

    if [ -d "$COMPAT_DIR/Proton-LayeredOverlay" ]; then
        return
    fi

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"; trap - RETURN' RETURN

    fetch_pinned "$OVERLAY_URL" "$OVERLAY_SHA256" "$tmp/overlay.tar.gz"
    tar -xzf "$tmp/overlay.tar.gz" -C "$COMPAT_DIR"
}

install_proton_ge
install_overlay
