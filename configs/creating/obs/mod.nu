# obs's collections and profiles rendered per machine (canvas, mic, webcam, encoders) from the repo seeds and the
# secret Streaming collection; backup carries obs's own edits back into them

use module.nu *
use converge.nu [recorded-hashes]

export const meta = {
    packages: {
        pacman: [
            lib32-obs-vkcapture obs-audio-wave-bin obs-pipewire-audio-capture obs-plugin-waveform-bin obs-studio
            obs-studio-plugin-browser obs-vkcapture websocat
            npm
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
        doc: "Base and output canvas of every profile and the repo collections (Bare, VirtualCam), WxH"
        label: "Canvas"
        scope: machine
    }
    mic: {
        type: string?
        default: null
        doc: "The pipewire source node every collection's Mic/Aux captures"
        label: "Microphone"
        scope: machine
    }
    webcam: {
        type: string?
        default: null
        doc: "The v4l2 device the VirtualCam collection's Camera captures, by-id so it survives replugging"
        label: "Webcam"
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
const CANVAS_FALLBACK = "1920x1080"
const HEADLESS_OUTPUT = '^HEADLESS-'
# the virtual camera sends raw YUYV: 4k at 30 fps is ~500 MB/s that every consumer scales per frame
const VIRTUALCAM_HEIGHT = 720
const STREAM_HEIGHT = 1080
const PORTAL_TOKEN = "RestoreToken"
const GLOBAL = {General: {AutomaticSearch: "true", SafeMode: "false", ConfirmOnExit: "true"}}
# obs 31+ reads the selection here, else it opens an empty Untitled; FirstRun unset opens the setup wizard
const USER = {
    Basic: {Profile: Streaming, ProfileDir: Streaming, SceneCollection: Streaming, SceneCollectionFile: Streaming.json}
    General: {FirstRun: "true"}
}
# obs never shows chromium's local network access prompt, so an https overlay could not reach discord's rpc
const LAUNCH_FLAGS = "--enable-unsafe-webgpu --enable-features=Vulkan --disable-features=LocalNetworkAccessChecks"

def vaapi-encodes [node: string, profile: string]: nothing -> bool {
    if (which vainfo | is-empty) { return false }
    ^vainfo --display drm --device $node | complete | get stdout | lines
    | any { $in =~ $'VAProfile($profile).*EncSlice' }
}

def --wrapped pactl-read [...args: string]: nothing -> oneof<string, nothing> {
    if (which pactl | is-empty) { return null }
    ^pactl ...$args | complete | if $in.exit_code == 0 { $in.stdout | str trim } else { null }
}

# The hardware node of a kind, never the default one, which follows the bar's picker and an agent's null sink;
# an external one over the built-in.
def audio-device [kind: string]: nothing -> oneof<string, nothing> {
    let nodes = pactl-read -f json list $kind
    if $nodes == null { return null }
    $nodes | from json | where properties."device.class"? == "sound"
    | sort-by {|n| $n.properties."device.bus"? == "pci" } name | get --optional 0.name
}

export def detect [cfg: record]: nothing -> record {
    let gpu = gpu-list | get --optional 0
    let monitor = try {
        ^hyprctl -j monitors | from json | where name !~ $HEADLESS_OUTPUT
        | sort-by {|m| -1 * $m.width * $m.height } name | first
    } catch { null }
    let node = $cfg.vaapi_render_node | default $gpu.by_path?
    let nvidia = $gpu.vendor? == "nvidia"
    let vaapi = {|profile| $node != null and not $nvidia and (vaapi-encodes $node $profile) }
    let h264 = if (do $vaapi H264) { "ffmpeg_vaapi_tex" } else if $nvidia { "obs_nvenc_h264_tex" } else { "obs_x264" }
    {
        vaapi_render_node: $gpu.by_path?
        canvas: (if $monitor == null { null } else { $"($monitor.width)x($monitor.height)" })
        mic: (audio-device sources)
        webcam: (glob /dev/v4l/by-id/*-video-index0 | sort | get --optional 0)
        monitor_device: (audio-device sinks)
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

# The values of the profiles' @KEY@ placeholders: this user's dirs, the machine's devices and encoders.
def profile-values [cfg: record]: nothing -> record {
    let size = canvas-size $cfg
    let fit = {|cap| let h = [$cap $size.h] | math min; {w: (($h * $size.w / $size.h / 2 | math round) * 2), h: $h} }
    let virtualcam = do $fit $VIRTUALCAM_HEIGHT
    let stream = do $fit $STREAM_HEIGHT
    {
        HOME: $nu.home-dir
        XDG_VIDEOS: (videos-dir)
        CANVAS_W: $size.w
        CANVAS_H: $size.h
        VIRTUALCAM_W: $virtualcam.w
        VIRTUALCAM_H: $virtualcam.h
        STREAM_RES: $"($stream.w)x($stream.h)"
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

# Rescales a collection laid out at another resolution to the canvas; the relative copies go, obs derives them anew.
def scene-fit [size: record]: record -> record {
    let scene = $in
    let from = $scene.resolution
    if $from.x == $size.w and $from.y == $size.h { return $scene }
    let scale = {|v| {x: ($v.x * $size.w / $from.x), y: ($v.y * $size.h / $from.y)} }
    $scene | update resolution {x: $size.w, y: $size.h} | update sources {
        each {|src|
            if $src.id != "scene" { return $src }
            $src | update settings.items {
                each {|item|
                    $item | update pos (do $scale $item.pos) | update bounds (do $scale $item.bounds)
                    | reject --optional pos_rel scale_rel scale_ref bounds_rel
                }
            }
        }
    }
}

def scene-mic [mic: oneof<string, nothing>]: record -> record {
    if $mic == null or $in.AuxAudioDevice1? == null { return $in }
    $in | update AuxAudioDevice1.settings.device_id $mic
}

# A collection for this machine: its mic, with --machine also its canvas and webcam (the shared Streaming layout stays).
def scene-render [cfg: record, src: path, --machine]: nothing -> string {
    let scene = open $src | scene-mic $cfg.mic
    if not $machine { return $"($scene | to json --indent 2)\n" }
    let miked = $scene | scene-fit (canvas-size $cfg)
    let cammed = if $cfg.webcam == null { $miked } else {
        $miked | update sources {
            each {|src| if $src.id == "v4l2_input" { $src | upsert settings.device_id $cfg.webcam } else { $src } }
        }
    }
    $"($cammed | to json --indent 2)\n"
}

# Keeps the live collection when it differs only in its portal token.
def scene-file [dest: path, text: string, mode: string]: nothing -> record {
    let live = if ($dest | path exists) { open --raw $dest } else { "" }
    let same = $live != "" and (($live | from json | strip-token) == ($text | from json | strip-token))
    file-text $dest (if $same { $live } else { $text }) --mode $mode
}

# Which repo collection a live one was last installed from, so backup can tell an edit obs has not loaded.
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

def repo-scenes []: nothing -> list<path> {
    glob ($HERE | path join scenes *.json) | sort
}

def scene-seed [seed: path]: nothing -> path {
    host-seed ($seed | path dirname) ($seed | path basename)
}

def scene-own [seed: path]: nothing -> path {
    host-file ($seed | path dirname) ($seed | path basename)
}

def secret [name: string]: nothing -> path {
    $env.DOTFILES | path join configs secrets keys $name
}

def obs-running []: nothing -> bool {
    (ps | where name == obs | is-not-empty)
}

export def link [cfg: record] {
    let obs = obs-dir
    let basic = $obs | path join basic
    let streaming = secret obs-Streaming.json
    let service = secret obs-service.json
    let scene = {|live, text, mode|
        [(scene-file $live $text $mode) (file-text (applied-file $live) ($text | scene-hash))]
    }
    let secret_scene = if (secret-is-plaintext $streaming) {
        (do $scene ($basic | path join scenes Streaming.json) (scene-render $cfg $streaming) "600")
        | append (file-text ($basic | path join scenes .from-secrets) "")
    } else { [] }
    let scenes = $secret_scene ++ (repo-scenes | each {|seed|
        do $scene ($basic | path join scenes ($seed | path basename)) (scene-render $cfg (scene-seed $seed) --machine) "644"
    })
    let profiles = glob ($HERE | path join profiles * *) | each {|src|
        let dest = $basic | path join ($src | path relative-to $HERE)
        match ($src | path basename) {
            "basic.ini" => (file-render $src $dest (profile-values $cfg))
            _ => (file-text $dest (vaapi-encoder $cfg $src))
        }
    }
    let state = $scenes ++ $profiles | decls-flatten
    # obs saves its loaded collection and profile on exit, over anything written under it
    if (obs-running) and ($state | any {|d| not ($d.target | path exists) or (open --raw $d.target) != $d.content }) {
        error make {msg: "obs runs, close it so its collections and profiles can be updated"}
    }
    let prefix = $nu.home-dir | path join $MCP_PREFIX
    let websocket = $obs | path join plugin_config obs-websocket config.json
    let npm_ci = [npm ci --no-audit --no-fund --prefix $prefix]
    [
        $state
        (if (secret-is-plaintext $service) {
            file-copy $service ($basic | path join profiles Streaming service.json) --mode 600
        } else { [] })
        (ini-merge ($obs | path join global.ini) $GLOBAL)
        (ini-merge ($obs | path join user.ini) $USER --missing-only)
        (if ($websocket | path exists) { [] } else { step websocket-init $websocket })
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

# Carries a live collection back to dest, unless src changed since link (an edit obs has not loaded).
# The portal token is this machine's, never stored.
def scene-back [cfg: record, live: path, src: path, dest: path, --machine]: nothing -> nothing {
    if not ($live | path exists) { return }
    let applied = applied-file $live
    if ($applied | path exists) and (open --raw $applied) != (scene-render $cfg $src --machine=$machine | scene-hash) {
        log-warn $"($src) has edits obs has not loaded, kept it; close obs and dot apply --user creating/obs"
        return
    }
    let saved = open $live | strip-token
    let saved = if $machine or $saved.AuxAudioDevice1?.settings?.device_id? != $cfg.mic { $saved } else {
        $saved | scene-mic (open $src | get --optional AuxAudioDevice1.settings.device_id)
    }
    mkdir ($dest | path dirname)
    $"($saved | to json --indent 2)\n" | save --force $dest
}

# Writes a live profile back to the repo: placeholders stay, paths under this user's dirs become placeholders again.
def profile-back [live: path, repo: path]: nothing -> nothing {
    let placeholders = ini-lines (open --raw $repo) | where {|r| $r.value != null and $r.value =~ '^@[A-Z_]+@$' }
    let videos = videos-dir
    ini-lines (open --raw $live) | each {|l|
        let kept = $placeholders | where section == $l.section and key == $l.key | get --optional 0.value
        if $kept != null { return $"($l.key)=($kept)" }
        if $l.key == null or not ($l.key | str ends-with "Path") { return $l.line }
        # videos first, it is under home
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
    scene-back $cfg $streaming (secret obs-Streaming.json) (secret obs-Streaming.json)
    for seed in (repo-scenes) {
        scene-back $cfg ($basic | path join scenes ($seed | path basename)) (scene-seed $seed) (scene-own $seed) --machine
    }
    let service = $basic | path join profiles Streaming service.json
    if ($service | path exists) { cp --force $service (secret obs-service.json) }
    let recorded = recorded-hashes
    for repo in (glob ($HERE | path join profiles * *)) {
        let live = $basic | path join ($repo | path relative-to $HERE)
        let saved = ($live | path exists) and (open --raw $live | hash sha256) != ($recorded | get --optional $live)
        if not $saved { continue }
        if ($repo | path basename) == "basic.ini" {
            profile-back $live $repo
        } else {
            $"(open $live | reject --optional vaapi_device | to json --indent 2)\n" | save --force $repo
        }
    }
}
