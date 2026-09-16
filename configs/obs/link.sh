#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v obs >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/obs-studio/basic/scenes/
mkdir -p ${HOME}/.config/obs-studio/basic/profiles/Untitled/

ln -sfn ${PWD}/Untitled.json ${HOME}/.config/obs-studio/basic/scenes/Untitled.json
ln -sfn ${PWD}/basic.ini ${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini
# global config: SafeMode off + AutomaticSearch on so a missing capture device
# auto-retries instead of prompting for every source on launch (issue 32)
[ -f ${HOME}/.config/obs-studio/global.ini ] || ln -sfn ${PWD}/global.ini ${HOME}/.config/obs-studio/global.ini

# obs-websocket, for the bar's OBS status widget
# (configs/quickshell/plugins/bar/widgets/obs-status.py). The widget reads the
# port and password straight out of this file, so this is the only place they
# exist — deliberately NOT tracked in git, and generated locally on first link
# rather than shipped, because a password in a public dotfiles repo is a
# password everyone has. An existing config is never touched: if the server was
# configured through the OBS UI, that is the authority.
#
# The password is base64url, so it carries no shell metacharacters and is safe
# to interpolate. `umask 077` in the subshell means the file is never briefly
# world-readable between creation and chmod.
OBS_WS_DIR="${HOME}/.config/obs-studio/plugin_config/obs-websocket"
if [ ! -f "${OBS_WS_DIR}/config.json" ]; then
	mkdir -p "${OBS_WS_DIR}"
	# set +x for the rest of the block: this script runs under `set -ex`, and
	# tracing it would print the generated password to the terminal and into
	# any log the link run is captured in.
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

# Patch the OBS desktop launcher with CEF/Chromium flags
OBS_FLAGS="--use-fake-ui-for-media-stream --enable-unsafe-webgpu --enable-features=Vulkan --disable-features=LocalNetworkAccessChecks,BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessSendPreflights,PrivateNetworkAccessRespectPreflightResults,LocalNetworkAccess"
OBS_DESKTOP_SRC=/usr/share/applications/com.obsproject.Studio.desktop
OBS_DESKTOP_DEST="${HOME}/.local/share/applications/com.obsproject.Studio.desktop"
if [ -f "${OBS_DESKTOP_SRC}" ]; then
	mkdir -p "$(dirname "${OBS_DESKTOP_DEST}")"
	cp "${OBS_DESKTOP_SRC}" "${OBS_DESKTOP_DEST}"
	sed -i "s|^Exec=obs.*|Exec=obs ${OBS_FLAGS}|" "${OBS_DESKTOP_DEST}"
	update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
fi
