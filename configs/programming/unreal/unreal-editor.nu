#!/usr/bin/env -S nu --no-config-file

# not 8765 (dot test's beacon) nor 8000 (vllm's socket)
const MCP_PORT = 8766
const EDITOR = "Engine/Binaries/Linux/UnrealEditor"
const ALL_TOOLSETS = "Engine/Plugins/Experimental/Toolsets/AllToolsets/AllToolsets.uplugin"
# both pull in the GameFeatures runtime, which logs load errors in every project without its asset manager rule
const TOOLSETS_SKIPPED = [GameFeaturesToolset ConversationToolset]

def --wrapped main [...args: string]: nothing -> nothing {
    # 5.8's sdl3 wayland driver renders at 1x and the compositor stretches it (blurry)
    $env.SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY = "1"
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let engine = [$env.UE_ROOT? ($data | path join unreal-engine) /opt/unreal-engine] | compact --empty
        | where { $in | path join $EDITOR | path exists } | get --optional 0
    if $engine == null { print -e "unreal-editor: no engine (set UE_ROOT)"; exit 1 }
    let toolsets = try {
        open --raw ($engine | path join $ALL_TOOLSETS) | from json
        | get Plugins.Name | where $it not-in $TOOLSETS_SKIPPED | str join ","
    } catch { "" }
    let enable_plugins = if ($toolsets | is-empty) { "ModelContextProtocol" } else { $"ModelContextProtocol,($toolsets)" }
    let zen_args = try {
        open --raw ($engine | path join Engine/Config/BaseEngine.ini) | lines
        | skip until { $in == "[Zen.AutoLaunch]" } | skip 1 | take until { str starts-with "[" }
        | where { str starts-with "ExtraArgs=" } | each { str substring 10.. } | str join "\n"
    } catch { "" }
    (exec ($engine | path join $EDITOR) ...$args
        $"-EnablePlugins=($enable_plugins)"
        -ModelContextProtocolStartServer $"-ModelContextProtocolPort=($MCP_PORT)"
        "-ini:Engine:[HTTPServer.Listeners]:DefaultBindAddress=127.0.0.1"
        $"-ini:Engine:[Zen.AutoLaunch]:ExtraArgs=($zen_args) --http-forceloopback"
        -UDPMESSAGING_TRANSPORT_ENABLE=false -notraceserver)
}
