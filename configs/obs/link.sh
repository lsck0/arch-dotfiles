#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/obs-studio/basic/scenes/
mkdir -p ${HOME}/.config/obs-studio/basic/profiles/Untitled/

ln -sf ${PWD}/Untitled.json ${HOME}/.config/obs-studio/basic/scenes/Untitled.json
ln -sf ${PWD}/basic.ini ${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini

# Patch the OBS desktop launcher with CEF/Chromium flags the embedded browser source needs
# for fugi.tech Reactive (and similar webcam + localhost tools):
#   --use-fake-ui-for-media-stream
#       auto-grant getUserMedia (mic/cam); CEF otherwise silently denies and
#       mic-reactive pages hang on "loading".
#   --enable-unsafe-webgpu --enable-features=Vulkan
#       enable WebGPU (Vulkan backend) for WebGPU-rendered overlays.
#   --disable-features=LocalNetworkAccessChecks,...
#       Chromium's Local/Private Network Access blocking (recent CEF) stops a
#       public https page connecting to 127.0.0.1. Reactive's Discord mode hits
#       the Discord RPC websocket on 127.0.0.1:6463-6472; without this it gets
#       ERR_CONNECTION_REFUSED and hangs on the loading splash.
# Writes a user override that shadows the packaged entry, surviving upgrades.
OBS_FLAGS="--use-fake-ui-for-media-stream --enable-unsafe-webgpu --enable-features=Vulkan --disable-features=LocalNetworkAccessChecks,BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessSendPreflights,PrivateNetworkAccessRespectPreflightResults,LocalNetworkAccess"
OBS_DESKTOP_SRC=/usr/share/applications/com.obsproject.Studio.desktop
OBS_DESKTOP_DEST="${HOME}/.local/share/applications/com.obsproject.Studio.desktop"
if [ -f "${OBS_DESKTOP_SRC}" ]; then
	mkdir -p "$(dirname "${OBS_DESKTOP_DEST}")"
	cp "${OBS_DESKTOP_SRC}" "${OBS_DESKTOP_DEST}"
	sed -i "s|^Exec=obs.*|Exec=obs ${OBS_FLAGS}|" "${OBS_DESKTOP_DEST}"
	update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
fi
