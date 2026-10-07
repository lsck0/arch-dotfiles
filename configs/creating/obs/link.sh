#!/usr/bin/env bash

basic="${HOME}/.config/obs-studio/basic"
mkdir -p "${basic}/scenes"

# scenes and the stream service carry stream tokens, so they live in secrets; readlink only once one exists
scene_secret="$DOTFILES/secrets/obs-Untitled.json"
if secret_is_plaintext "${scene_secret}"; then
	ln -sfn "$(readlink -f "${scene_secret}")" "${basic}/scenes/Untitled.json"
	touch "${basic}/scenes/.from-secrets"
fi
link_into "${basic}/profiles/Untitled" basic.ini streamEncoder.json recordEncoder.json
service_secret="$DOTFILES/secrets/obs-service.json"
if secret_is_plaintext "${service_secret}"; then
	ln -sfn "$(readlink -f "${service_secret}")" "${basic}/profiles/Untitled/service.json"
fi
# no safe-mode prompt for a missing capture device (issue 32)
[[ -f "${HOME}/.config/obs-studio/global.ini" ]] || ln -sfn "${PWD}/global.ini" "${HOME}/.config/obs-studio/global.ini"

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
fi

# cef flags for the desktop launcher: gpu acceleration for browser sources only
# the obs-websocket dock is same-origin localhost, so no private-network override is needed;
# media-stream auto-grant is left off, obs captures cam/mic through its own native sources
OBS_FLAGS="--enable-unsafe-webgpu --enable-features=Vulkan"
desktop_override com.obsproject.Studio.desktop "s|^Exec=obs.*|Exec=obs ${OBS_FLAGS}|"
