#!/usr/bin/env -S nu --no-config-file

# 8766, not 8765 (dot test's beacon) nor 8000 (vllm's socket)
const MCP_PORT = 8766
const EDITOR = "Engine/Binaries/Linux/UnrealEditor"
const ALL_TOOLSETS = "Engine/Plugins/Experimental/Toolsets/AllToolsets/AllToolsets.uplugin"
# both pull in the GameFeatures runtime, which opens every project without its asset manager rule on a load errors log
const TOOLSETS_SKIPPED = [GameFeaturesToolset ConversationToolset]

def --wrapped main [...args: string]: nothing -> nothing {
    # 5.8's sdl3 wayland driver renders at 1x and the compositor stretches it to the fractional scale (blurry)
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
    # no listener has auth and fw-inbound trusts containers, vms and wg0: http and zen on loopback, udp bus and trace off
    (exec ($engine | path join $EDITOR) ...$args
        $"-EnablePlugins=ModelContextProtocol,($toolsets)"
        -ModelContextProtocolStartServer $"-ModelContextProtocolPort=($MCP_PORT)"
        "-ini:Engine:[HTTPServer.Listeners]:DefaultBindAddress=127.0.0.1"
        $"-ini:Engine:[Zen.AutoLaunch]:ExtraArgs=($zen_args) --http-forceloopback"
        -UDPMESSAGING_TRANSPORT_ENABLE=false -notraceserver)
}
