use module.nu *
use converge.nu [recorded-hashes]

export const meta = {
    packages: {
        pacman: [
            lib32-obs-vkcapture obs-audio-wave-bin obs-pipewire-audio-capture obs-plugin-waveform-bin obs-studio
            obs-studio-plugin-browser obs-vkcapture websocat
        ]
    }
    backup: {secrets: true}
}

export const options = {
    vaapi_render_node: {
        type: string?
        default: null
        doc: "The /dev/dri render node the vaapi encoders use, by-path so it survives reboots"
        label: "VAAPI render node"
        scope: machine
    }
    canvas: {
        type: string?
        default: null
        doc: "Base and output canvas of every profile and the Fullscreen collection, WxH"
        label: "Canvas"
        scope: machine
    }
    mic: {
        type: string?
        default: null
        doc: "The pipewire source node the Fullscreen collection's Mic/Aux captures"
        label: "Microphone"
        scope: machine
    }
    monitor_device: {
        type: string?
        default: null
        doc: "The pipewire sink node obs monitors audio on"
        label: "Monitoring device"
        scope: machine
    }
    record_encoder: {
        type: string?
        default: null
        doc: "The recording encoder of the Recording and Streaming profiles"
        label: "Recording encoder"
        choices: [
            av1_ffmpeg_vaapi_tex hevc_ffmpeg_vaapi_tex ffmpeg_vaapi_tex obs_nvenc_av1_tex obs_nvenc_h264_tex obs_x264
        ]
        scope: machine
    }
    stream_encoder: {
        type: string?
        default: null
        doc: "The streaming encoder; h264 is what every ingest takes"
        label: "Streaming encoder"
        choices: [ffmpeg_vaapi_tex obs_nvenc_h264_tex obs_x264]
        scope: machine
    }
}

const HERE = path self | path dirname
const OBS = ".config/obs-studio"
const MCP_PREFIX = ".local/share/obs-mcp"
const WEBSOCKET_PORT = 4455
# the scene collection without the portal RestoreToken obs writes per machine, as the backup stores it
const CANVAS_FALLBACK = "1920x1080"
const PORTAL_TOKEN = "RestoreToken"
const GLOBAL = {General: {AutomaticSearch: "true", SafeMode: "false", ConfirmOnExit: "true"}}
# since obs 31 the selection lives in user.ini [Basic]; without it obs opens an empty Untitled profile and collection
const SELECTION = {
    Basic: {Profile: Streaming, ProfileDir: Streaming, SceneCollection: Streaming, SceneCollectionFile: Streaming.json}
}
# cef flags of the launcher: gpu acceleration for browser sources only; cam and mic come through obs's own sources
const LAUNCH_FLAGS = "--enable-unsafe-webgpu --enable-features=Vulkan"

# before the install pass, or as root with no session, there is no vainfo or pulse server: nothing to report
def vaapi-encodes [node: string, profile: string]: nothing -> bool {
    if (which vainfo | is-empty) { return false }
    ^vainfo --display drm --device $node | complete | get stdout | lines
    | any { $in =~ $'VAProfile($profile).*EncSlice' }
}

def --wrapped pactl-read [...args: string]: nothing -> oneof<string, nothing> {
    if (which pactl | is-empty) { return null }
    ^pactl ...$args | complete | if $in.exit_code == 0 { $in.stdout | str trim } else { null }
}

export def detect [cfg: record]: nothing -> record {
    let gpu = gpu-list | get --optional 0
    let monitor = try { ^hyprctl -j monitors | from json | sort-by focused --reverse | first } catch { null }
    let node = $cfg.vaapi_render_node | default $gpu.by_path?
    let nvidia = $gpu.vendor? == "nvidia"
    let vaapi = {|profile| $node != null and not $nvidia and (vaapi-encodes $node $profile) }
    let h264 = if (do $vaapi H264) { "ffmpeg_vaapi_tex" } else if $nvidia { "obs_nvenc_h264_tex" } else { "obs_x264" }
    {
        vaapi_render_node: $gpu.by_path?
        canvas: (if $monitor == null { null } else { $"($monitor.width)x($monitor.height)" })
        mic: (pactl-read get-default-source)
        monitor_device: (pactl-read get-default-sink)
        record_encoder: (if (do $vaapi AV1) { "av1_ffmpeg_vaapi_tex" } else { $h264 })
        stream_encoder: $h264
    }
}

def obs-dir []: nothing -> path {
    $nu.home-dir | path join $OBS
}

def videos-dir []: nothing -> path {
    try { ^xdg-user-dir VIDEOS | str trim } catch { $nu.home-dir | path join Videos }
}

def canvas-size [cfg: record]: nothing -> record {
    $cfg.canvas | default $CANVAS_FALLBACK | parse "{w}x{h}" | get 0 | {w: ($in.w | into int), h: ($in.h | into int)}
}

def sink-name [node: string]: nothing -> string {
    pactl-read -f json list sinks | if $in == null { $node } else { from json | where name == $node | get --optional 0.description | default $node }
}

# the profiles' ini keep this user's dirs and the machine's devices and encoders as @KEY@ placeholders
def profile-values [cfg: record]: nothing -> record {
    let size = canvas-size $cfg
    {
        HOME: $nu.home-dir
        XDG_VIDEOS: (videos-dir)
        CANVAS_W: $size.w
        CANVAS_H: $size.h
        MONITOR_DEVICE: ($cfg.monitor_device | default default)
        MONITOR_NAME: (if $cfg.monitor_device == null { "Default" } else { sink-name $cfg.monitor_device })
        RECORD_ENCODER: $cfg.record_encoder
        STREAM_ENCODER: $cfg.stream_encoder
    }
}

def strip-token []: record -> record {
    update sources {|s|
        $s.sources | each {|src|
            if ($src.settings? | describe) !~ "^record" { return $src }
            $src | update settings { reject --optional $PORTAL_TOKEN }
        }
    }
}

def scene-render [cfg: record, src: path, --machine]: nothing -> string {
    let scene = open $src
    if not $machine { return $"($scene | to json --indent 2)\n" }
    let size = canvas-size $cfg
    let sized = if $cfg.canvas == null { $scene } else {
        $scene | update resolution {x: $size.w, y: $size.h} | update sources {|s|
            $s.sources | each {|src|
                if $src.id != "scene" { return $src }
                let bounds = {x: ($size.w | into float), y: ($size.h | into float)}
                $src | update settings.items {|i|
                    $i.settings.items | each {|item|
                        if $item.name == "Screen Capture" { $item | update bounds $bounds } else { $item }
                    }
                }
            }
        }
    }
    let miked = if $cfg.mic == null { $sized } else { $sized | update AuxAudioDevice1.settings.device_id $cfg.mic }
    $"($miked | to json --indent 2)\n"
}

# obs saves by renaming to .bak and writing anew, so a copy; one differing only in its portal token is kept
def scene-file [dest: path, text: string, mode: string]: nothing -> record {
    let live = if ($dest | path exists) { open --raw $dest } else { "" }
    let same = $live != "" and (($live | from json | strip-token) == ($text | from json | strip-token))
    file-text $dest (if $same { $live } else { $text }) --mode $mode
}

# which repo collection a live one was last installed from, so the backup can tell an edit obs has not loaded
def applied-file [live: path]: nothing -> path {
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)
    $state | path join dotfiles obs $"($live | path basename).applied"
}

def scene-hash []: string -> string {
    from json | strip-token | to json --raw | hash sha256
}

def vaapi-encoder [cfg: record, src: path]: nothing -> string {
    let json = open $src
    let json = if $cfg.vaapi_render_node == null { $json } else { $json | upsert vaapi_device $cfg.vaapi_render_node }
    $"($json | to json --indent 2)\n"
}

def secret [name: string]: nothing -> path {
    $env.DOTFILES | path join secrets $name
}

def obs-running []: nothing -> bool {
    (ps | where name == obs | is-not-empty)
}

export def link [cfg: record] {
    let obs = obs-dir
    let basic = $obs | path join basic
    # the Streaming collection carries stream tokens (alert browser sources), so it lives in secrets
    let streaming = secret obs-Streaming.json
    let service = secret obs-service.json
    let scene = {|live, text, mode|
        [(scene-file $live $text $mode) (file-text (applied-file $live) ($text | scene-hash))]
    }
    let secret_scene = if (secret-is-plaintext $streaming) {
        (do $scene ($basic | path join scenes Streaming.json) (scene-render $cfg $streaming) "600")
        | append (file-text ($basic | path join scenes .from-secrets) "")
    } else { [] }
    # no tokens, so in the repo
    let fullscreen = scene-render $cfg ($HERE | path join scenes Fullscreen.json) --machine
    let scenes = $secret_scene ++ (do $scene ($basic | path join scenes Fullscreen.json) $fullscreen "644")
    let profiles = glob ($HERE | path join profiles * *) | each {|src|
        let dest = $basic | path join ($src | path relative-to $HERE)
        match ($src | path basename) {
            "basic.ini" => (file-render $src $dest (profile-values $cfg))
            _ => (file-text $dest (vaapi-encoder $cfg $src))
        }
    }
    let state = $scenes ++ $profiles | decls-flatten
    # obs saves its loaded collection and profile over the live copies on exit, one written under a running obs is lost
    if (obs-running) and ($state | any {|d| not ($d.target | path exists) or (open --raw $d.target) != $d.content }) {
        error make {msg: "obs runs, close it so its collections and profiles can be updated"}
    }
    let prefix = $nu.home-dir | path join $MCP_PREFIX
    let websocket = $obs | path join plugin_config obs-websocket config.json
    let npm_ci = [npm ci --no-audit --no-fund --prefix $prefix]
    [
        $state
        # the stream key belongs to the Streaming profile only; without it obs asks for one (Settings > Stream)
        (if (secret-is-plaintext $service) {
            file-copy $service ($basic | path join profiles Streaming service.json) --mode 600
        } else { [] })
        (ini-merge ($obs | path join global.ini) $GLOBAL)
        (ini-merge ($obs | path join user.ini) $SELECTION --missing-only)
        (if ($websocket | path exists) { [] } else { step websocket-init $websocket })
        # obs-mcp pinned by the committed lockfile and installed from it offline (npm ci), never npx at start
        (file-copy ($HERE | path join mcp package.json) ($prefix | path join package.json))
        (file-copy ($HERE | path join mcp package-lock.json) ($prefix | path join package-lock.json) --then $npm_ci)
        (exec obs-mcp-install $npm_ci --creates ($prefix | path join node_modules .bin obs-mcp))
        (link-commands obs-mcp.nu)
        (json-merge ($nu.home-dir | path join .claude.json) [
            (json-set [mcpServers obs-mcp] {
                type: stdio, command: ($nu.home-dir | path join .local bin obs-mcp), args: []
            })
        ])
        (desktop-override com.obsproject.Studio.desktop {
            $in | str replace --all --regex '(?m)^Exec=obs.*' $"Exec=obs ($LAUNCH_FLAGS)"
        })
    ]
}

export def websocket-init [file: path]: nothing -> nothing {
    mkdir ($file | path dirname)
    let password = random chars --length 32
    {
        alerts_enabled: false, auth_required: true, first_load: false, server_enabled: true
        server_password: $password, server_port: $WEBSOCKET_PORT
    } | to json --indent 4 | save $file
    chmod 600 $file
}

# unless the repo's copy changed since link: obs has not loaded that edit and would save its old state over it
def scene-back [cfg: record, live: path, repo: path, --machine]: nothing -> nothing {
    if not ($live | path exists) { return }
    let applied = applied-file $live
    if ($applied | path exists) and (open --raw $applied) != (scene-render $cfg $repo --machine=$machine | scene-hash) {
        log-warn $"($repo) has edits obs has not loaded, kept it; close obs and dot link creating/obs"
        return
    }
    if $machine {
        $"(open $live | strip-token | to json --indent 2)\n" | save --force $repo
    } else {
        cp --force $live $repo
    }
}

# placeholder lines stay placeholders, a path under this user's dirs becomes one again (videos first, it is under home)
def profile-back [live: path, repo: path]: nothing -> nothing {
    let placeholders = ini-lines (open --raw $repo) | where {|r| $r.value != null and $r.value =~ '^@[A-Z_]+@$' }
    let videos = videos-dir
    ini-lines (open --raw $live) | each {|l|
        let kept = $placeholders | where section == $l.section and key == $l.key | get --optional 0.value
        if $kept != null { return $"($l.key)=($kept)" }
        if $l.key == null or not ($l.key | str ends-with "Path") { return $l.line }
        let path = if $l.value == $videos or ($l.value | str starts-with $"($videos)/") {
            $l.value | str replace $videos "@XDG_VIDEOS@"
        } else if $l.value == $nu.home-dir or ($l.value | str starts-with $"($nu.home-dir)/") {
            $l.value | str replace $nu.home-dir "@HOME@"
        } else { $l.value }
        $"($l.key)=($path)"
    } | str join "\n" | $"($in)\n" | save --force $repo
}

def ini-lines [text: string]: nothing -> table {
    $text | lines | reduce --fold {section: "", rows: []} {|line, acc|
        let section = $line | parse --regex '^\[(?<s>.*)\]$' | get --optional 0.s | default $acc.section
        let kv = $line | parse --regex '^(?<key>[A-Za-z0-9_]+)=(?<value>.*)$' | get --optional 0
        let row = {section: $section, key: $kv.key?, value: $kv.value?, line: $line}
        {section: $section, rows: ($acc.rows | append $row)}
    } | get rows
}

export def backup [cfg: record]: nothing -> nothing {
    let basic = obs-dir | path join basic
    let streaming = $basic | path join scenes Streaming.json
    if ($streaming | path exists) {
        secret-seed-guard ($basic | path join scenes .from-secrets) (secret obs-Streaming.json) $streaming
    }
    scene-back $cfg $streaming (secret obs-Streaming.json)
    scene-back $cfg ($basic | path join scenes Fullscreen.json) ($HERE | path join scenes Fullscreen.json) --machine
    let service = $basic | path join profiles Streaming service.json
    if ($service | path exists) { cp --force $service (secret obs-service.json) }
    let recorded = recorded-hashes
    for repo in (glob ($HERE | path join profiles * *)) {
        let live = $basic | path join ($repo | path relative-to $HERE)
        # one obs never saved over holds nothing of obs's, and the repo's may be newer
        let saved = ($live | path exists) and (open --raw $live | hash sha256) != ($recorded | get --optional $live)
        if not $saved { continue }
        if ($repo | path basename) == "basic.ini" {
            profile-back $live $repo
        } else {
            $"(open $live | reject --optional vaapi_device | to json --indent 2)\n" | save --force $repo
        }
    }
}
