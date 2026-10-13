#!/usr/bin/env bash

basic="${HOME}/.config/obs-studio/basic"
mkdir -p "${basic}/scenes"

# the Streaming collection carries stream tokens (alert browser sources), so it lives in secrets; link once unlocked
scene_secret="$DOTFILES/secrets/obs-Streaming.json"
if secret_is_plaintext "${scene_secret}"; then
	link_as "$(readlink -f "${scene_secret}")" "${basic}/scenes/Streaming.json"
	touch "${basic}/scenes/.from-secrets"
fi
# the Fullscreen collection (one screen capture + desktop/mic audio, no overlays) holds no tokens, so it lives in the repo
link_into "${basic}/scenes" scenes/Fullscreen.json

# one profile per purpose: Streaming (service + stream encoder, record as backup), Recording (local AV1 only),
# VirtualCam (virtual camera only, no encode). each profile is standalone OBS config
for p in profiles/*/; do
	dir="${basic}/profiles/$(basename "$p")"
	mkdir -p "${dir}"
	# the ini is static, so symlink it
	for f in "$p"*.ini; do [ -e "$f" ] && link_into "${dir}" "$f"; done
	# the encoder json keeps no vaapi_device in the repo (machine-agnostic); copy it and inject this box's render node
	for f in "$p"*Encoder.json; do
		[ -e "$f" ] || continue
		cp -f "$f" "${dir}/${f##*/}"
		[ -n "${VAAPI_RENDER_NODE:-}" ] && json_update "${dir}/${f##*/}" --arg d "$VAAPI_RENDER_NODE" '.vaapi_device=$d'
	done
done

# the stream key belongs to the Streaming profile only
service_secret="$DOTFILES/secrets/obs-service.json"
if secret_is_plaintext "${service_secret}"; then
	link_as "$(readlink -f "${service_secret}")" "${basic}/profiles/Streaming/service.json"
fi

# no safe-mode prompt for a missing capture device (issue 32), and a default profile/collection so OBS opens ready
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
