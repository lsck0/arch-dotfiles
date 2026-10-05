#!/usr/bin/env bash
# gamemode [custom] hook: strip desktop effects and pause background timers while a game runs
cd "$(dirname "$(readlink -f "$0")")" || exit 1
source ../../toggles/lib.sh

SHADER_TOGGLE=../../toggles/toggle-shader.sh
TRMNL_TIMER=trmnl-claude.timer
# local inference holds the whole gpu vram; free it for the game
# the socket reactivates vllm on the next client, so only ollama is restored
VLLM_PROXY=vllm-proxy.service
OLLAMA=ollama.service

case "${1:-}" in
start)
    toggle_set_volatile gamemode-shader "$("$SHADER_TOGGLE" get)"
    "$SHADER_TOGGLE" off
    # hyprland_powersave.lua drops blur, shadows and animations while this is set
    toggle_set_volatile gamemode on
    hyprctl reload config-only >/dev/null
    systemctl --user stop "$TRMNL_TIMER"
    systemctl is-active -q "$VLLM_PROXY" && systemctl stop "$VLLM_PROXY"
    if systemctl is-active -q "$OLLAMA"; then
        toggle_set_volatile gamemode-ollama on
        systemctl stop "$OLLAMA"
    fi
    ;;
end)
    rm -f "$TOGGLES_RUNTIME_DIR/gamemode"
    hyprctl reload config-only >/dev/null
    shader=$(toggle_get_volatile gamemode-shader)
    # custom is a shader toggle-shader.sh cannot load by name
    if [[ "$shader" != custom && "$("$SHADER_TOGGLE" get)" != "$shader" ]]; then
        "$SHADER_TOGGLE" "$shader"
    fi
    if systemctl --user is-enabled -q "$TRMNL_TIMER"; then
        systemctl --user start "$TRMNL_TIMER"
    fi
    if [[ "$(toggle_get_volatile gamemode-ollama)" == on ]]; then
        rm -f "$TOGGLES_RUNTIME_DIR/gamemode-ollama"
        systemctl start "$OLLAMA"
    fi
    ;;
*)
    echo "usage: $(basename "$0") {start|end}" >&2
    exit 1
    ;;
esac
