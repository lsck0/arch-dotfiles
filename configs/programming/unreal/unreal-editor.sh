#!/usr/bin/env bash
# the editor with epic's own mcp server (engine plugin ModelContextProtocol + its toolsets) on loopback, enabled for
# this launch only: nothing lands in the project's .uproject or the engine. claude's unreal-mcp entry (link.sh) points
# here; the server lives as long as the editor and has no auth, so it never binds beyond 127.0.0.1. 8765, not its
# default 8000: vllm's socket holds that
set -euo pipefail

MCP_PORT=8765
# 5.8 runs on sdl3's wayland driver at 1x and the compositor stretches it to the fractional scale (blurry); this makes
# sdl draw at the display's real pixels and hand unreal the scale, which its high-dpi slate then applies itself
export SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=1

for engine in ${UE_ROOT:+"$UE_ROOT"} "${XDG_DATA_HOME:-${HOME}/.local/share}/unreal-engine" /opt/unreal-engine; do
    if [[ -x "${engine}/Engine/Binaries/Linux/UnrealEditor" ]]; then
        # the .uproject has to come first, after a flag the editor opens its project browser instead
        exec "${engine}/Engine/Binaries/Linux/UnrealEditor" "$@" \
            -EnablePlugins=ModelContextProtocol,AllToolsets \
            -ModelContextProtocolStartServer -ModelContextProtocolPort="$MCP_PORT"
    fi
done
echo "unreal-editor: no engine (set UE_ROOT)" >&2
exit 1
