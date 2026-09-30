#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v obs >/dev/null 2>&1; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/obs-studio/basic/scenes/"
mkdir -p "${HOME}/.config/obs-studio/basic/profiles/Untitled/"

# scenes carry stream tokens, so they live in secrets
ln -sfn "$(readlink -f ../secrets/obs-Untitled.json)" "${HOME}/.config/obs-studio/basic/scenes/Untitled.json"
ln -sfn "${PWD}/basic.ini" "${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini"
# no safe-mode prompt for a missing capture device (issue 32)
[ -f "${HOME}/.config/obs-studio/global.ini" ] || ln -sfn "${PWD}/global.ini" "${HOME}/.config/obs-studio/global.ini"

# obs-websocket for the bar's obs widget
OBS_WS_DIR="${HOME}/.config/obs-studio/plugin_config/obs-websocket"
if [ ! -f "${OBS_WS_DIR}/config.json" ]; then
	mkdir -p "${OBS_WS_DIR}"
	# keep the password out of the trace
	set +x
	OBS_WS_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=\n')"
	(
		umask 077
		cat >"${OBS_WS_DIR}/config.json" <<-EOF
			{
			    "alerts_enabled": false,
			    "auth_required": true,
			    "first_load": false,
			    "server_enabled": true,
			    "server_password": "${OBS_WS_PASSWORD}",
			    "server_port": 4455
			}
		EOF
	)
	chmod 600 "${OBS_WS_DIR}/config.json"
	unset OBS_WS_PASSWORD
	set -x
fi

# cef flags for the desktop launcher
OBS_FLAGS="--use-fake-ui-for-media-stream --enable-unsafe-webgpu --enable-features=Vulkan --disable-features=LocalNetworkAccessChecks,BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessSendPreflights,PrivateNetworkAccessRespectPreflightResults,LocalNetworkAccess"
OBS_DESKTOP_SRC=/usr/share/applications/com.obsproject.Studio.desktop
OBS_DESKTOP_DEST="${HOME}/.local/share/applications/com.obsproject.Studio.desktop"
if [ -f "${OBS_DESKTOP_SRC}" ]; then
	mkdir -p "$(dirname "${OBS_DESKTOP_DEST}")"
	cp "${OBS_DESKTOP_SRC}" "${OBS_DESKTOP_DEST}"
	sed -i "s|^Exec=obs.*|Exec=obs ${OBS_FLAGS}|" "${OBS_DESKTOP_DEST}"
	update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
fi
