#!/usr/bin/env -S nu --no-config-file
# the editor with epic's own mcp server (engine plugin ModelContextProtocol + its toolsets), enabled for this launch
# only: nothing lands in the project's .uproject or the engine. claude's unreal-mcp entry (mod.nu) points here; the
# server lives as long as the editor and has no auth, so it must never leave loopback. fw-inbound keeps the home lan
# off these ports, but it accepts everything from containers, vms, waydroid and wg0, so every listener the editor
# starts is pinned here instead: ue's HTTPServer binds every interface by default (the -Port flag only sets the port),
# so the mcp one goes to 127.0.0.1; zenserver (the ddc, 8558) gets --http-forceloopback on top of the engine's own
# args; the udp message bus (6666 multicast and a unicast port, for session frontend and multi-user) is off; and the
# trace server (1981, 1989) is not started, `UnrealTraceServer fork` starts it for a live insights session. tracelog's
# own control port (1985) still binds every interface: the engine has no switch for it.

# 8766, not 8765 (dot test's beacon) nor 8000 (vllm's socket)
const MCP_PORT = 8766
const EDITOR = "Engine/Binaries/Linux/UnrealEditor"
const ALL_TOOLSETS = "Engine/Plugins/Experimental/Toolsets/AllToolsets/AllToolsets.uplugin"
# AllToolsets' own list minus the two that enable the GameFeatures runtime (GameFeaturesToolset itself, and
# ConversationToolset through CommonConversation): with it every project without a GameFeatureData asset manager rule
# opens on a Load Errors log
const TOOLSETS_SKIPPED = [GameFeaturesToolset ConversationToolset]

def --wrapped main [...args: string]: nothing -> nothing {
    # 5.8 runs on sdl3's wayland driver at 1x and the compositor stretches it to the fractional scale (blurry); this
    # makes sdl draw at the display's real pixels and hand unreal the scale, which its high-dpi slate then applies
    $env.SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY = "1"
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let engine = [$env.UE_ROOT? ($data | path join unreal-engine) /opt/unreal-engine] | compact --empty
        | where { $in | path join $EDITOR | path exists } | get --optional 0
    if $engine == null { print -e "unreal-editor: no engine (set UE_ROOT)"; exit 1 }
    let toolsets = open --raw ($engine | path join $ALL_TOOLSETS) | from json
        | get Plugins.Name | where $it not-in $TOOLSETS_SKIPPED | str join ","
    let zen_args = open --raw ($engine | path join Engine/Config/BaseEngine.ini) | lines
        | skip until { $in == "[Zen.AutoLaunch]" } | skip 1 | take until { str starts-with "[" }
        | where { str starts-with "ExtraArgs=" } | each { str substring 10.. } | str join "\n"
    # the .uproject has to come first, after a flag the editor opens its project browser instead
    (exec ($engine | path join $EDITOR) ...$args
        $"-EnablePlugins=ModelContextProtocol,($toolsets)"
        -ModelContextProtocolStartServer $"-ModelContextProtocolPort=($MCP_PORT)"
        "-ini:Engine:[HTTPServer.Listeners]:DefaultBindAddress=127.0.0.1"
        $"-ini:Engine:[Zen.AutoLaunch]:ExtraArgs=($zen_args) --http-forceloopback"
        -UDPMESSAGING_TRANSPORT_ENABLE=false -notraceserver)
}
