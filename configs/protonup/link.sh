#!/usr/bin/env bash

set -ex

mkdir -p ~/.steam/root/compatibilitytools.d
mkdir -p ~/.steam/steam/compatibilitytools.d
ln -sf ~/.steam/root/compatibilitytools.d ~/.steam/steam/compatibilitytools.d

/usr/bin/protonup -y

wget https://github.com/thaylorz/proton-ge-custom/releases/download/proton-layered-overlay-v1/Proton-LayeredOverlay.tar.gz
tar -xzf Proton-LayeredOverlay.tar.gz -C ~/.steam/root/compatibilitytools.d/
rm Proton-LayeredOverlay.tar.gz
