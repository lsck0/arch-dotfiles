use module.nu *

export const meta = {
    packages: {
        pacman: [
            app2unit bemenu-wayland brightnessctl cpio ddcutil grim hyprcursor hypridle hyprland hyprlock hyprpicker
            hyprpm libnotify libx11 mission-center pavucontrol playerctl polkit polkit-kde-agent qt5-wayland
            qt6-wayland rose-pine-cursor rose-pine-hyprcursor slurp wayland wayland-boomer-git wl-clipboard
            xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xdg-desktop-portal-kde xorg-server xorg-xauth
            xorg-xhost xorg-xinput xorg-xwayland ydotool
        ]
    }
}

export const options = {
    monitors: {
        type: list<record>?
        default: null
        doc: "One hl.monitor per output: output, mode, position, scale; detected from the connected outputs, any other output gets its preferred mode and an auto scale"
        label: "Monitors"
        group: display
        scope: machine
    }
    main_monitor: {
        type: string?
        default: null
        doc: "The output holding workspace 1, the bar's notifications, steam's toasts and the tablet; detected: the internal panel, else the largest, leftmost on a tie"
        label: "Main monitor"
        group: display
        scope: machine
    }
    workspaces: {
        type: record?
        default: null
        doc: "Workspace to output; detected: the first ceil(10 / outputs) on the main monitor, the rest split over the others left to right"
        label: "Workspace layout"
        group: display
        scope: machine
    }
    xwayland_scale: {
        type: int?
        default: null
        doc: "GDK_SCALE and QT_AUTO_SCREEN_SCALE_FACTOR for X11 apps (force_zero_scaling); detected: the main monitor's scale rounded, else 1 on a laptop and 2 elsewhere"
        label: "XWayland scale"
        group: display
        min: 1
        max: 4
        scope: machine
    }
    app_workspaces: {
        type: list<record>
        default: []
        doc: "Homes for apps by window class: {class, workspace, silent}; silent opens them without focus"
        label: "App workspaces"
        group: display
    }
    kb_layout: {
        type: string?
        default: null
        doc: "xkb layout; detected from the keymap localectl set (/etc/X11/xorg.conf.d/00-keyboard.conf)"
        label: "Keyboard layout"
        group: input
    }
    kb_variant: {
        type: string?
        default: null
        doc: "xkb variant; detected like the layout"
        label: "Keyboard variant"
        group: input
    }
    kb_options: {
        type: string?
        default: null
        doc: "xkb options, comma separated (ctrl:nocaps); detected like the layout"
        label: "Keyboard options"
        group: input
    }
    pointer_sensitivity: {
        type: float
        default: 0.0
        doc: "libinput pointer acceleration, -1 to 1"
        label: "Pointer sensitivity"
        group: input
        min: -1.0
        max: 1.0
        step: 0.05
    }
    natural_scroll: {
        type: bool
        default: false
        doc: "Touchpad content follows the fingers"
        label: "Natural scrolling"
        group: input
    }
    idle_dim_s: {type: int, default: 900, doc: "Idle seconds until the screens dim", label: "Dim after", group: idle, min: 60, apply: relogin}
    idle_lock_s: {type: int, default: 1200, doc: "Idle seconds until the session locks", label: "Lock after", group: idle, min: 60, apply: relogin}
    idle_dpms_s: {type: int, default: 2100, doc: "Idle seconds until the screens go off", label: "Screens off after", group: idle, min: 60, apply: relogin}
    idle_suspend_s: {type: int, default: 2400, doc: "Idle seconds until suspend, unless an agent works or an inhibitor holds", label: "Suspend after", group: idle, min: 60, apply: relogin}
    idle_suspend_saver_s: {type: int, default: 600, doc: "Idle seconds until suspend in power saver", label: "Suspend in power saver after", group: idle, min: 60, apply: relogin}
}

const CONFIG_DIR = ".config/hypr"
const LUA = [
    hyprland.lua hyprland_autostart.lua hyprland_cursor.lua hyprland_input.lua hyprland_keybindings.lua
    hyprland_layout.lua hyprland_misc.lua hyprland_monitors.lua hyprland_plugins.lua hyprland_powersave.lua
    hyprland_windowrules.lua hyprland_windows.lua wal_colors.lua hyprlock.conf
]
# hypridle and the quickshell lock run these by their path under the config dir
const COMMANDS = [lockscreen-stats.nu quickshell-lock-launch.nu screen-dim.nu]
const KEYBOARD_CONF = "/etc/X11/xorg.conf.d/00-keyboard.conf"
const INTERNAL_PANEL = '^(eDP|LVDS|DSI)-'
const WORKSPACE_COUNT = 10
# logical dpi a scale aims for, a laptop is seen from closer: 1 on a 14" 1080p panel, 1.5 on a 27" 4k
const TARGET_DPI = {laptop: 150.0, desktop: 110.0}
const MM_PER_INCH = 25.4
const SCALES = [1.0 1.25 1.5 1.666667 2.0 2.5 3.0]

def outputs-live []: nothing -> table {
    if ($env.HYPRLAND_INSTANCE_SIGNATURE? | is-empty) { return [] }
    # agents' headless outputs are never a real monitor
    # a stale signature (a shell from before a compositor restart) must not cost detect its keyboard half
    try { ^hyprctl -j monitors | from json } catch { [] } | where name !~ '^HEADLESS-' | sort-by x
}

def mode-best [modes: list<string>]: nothing -> string {
    $modes | parse --regex '(?<w>\d+)x(?<h>\d+)@(?<hz>[\d.]+)Hz' | into int w h | into float hz
    | sort-by --reverse {|m| [($m.w * $m.h) $m.hz] } | first | $"($in.w)x($in.h)@($in.hz | math round)"
}

def scale-for [output: record]: nothing -> float {
    if $output.physicalWidth <= 0 { return 1.0 }
    let target = if $env.FORM_FACTOR == laptop { $TARGET_DPI.laptop } else { $TARGET_DPI.desktop }
    let wanted = $output.width / ($output.physicalWidth / $MM_PER_INCH) / $target
    $SCALES | sort-by {|s| $s - $wanted | math abs } | first
}

def monitors-detect []: nothing -> list<record> {
    outputs-live | reduce --fold {x: 0, rows: []} {|o, acc|
        let scale = scale-for $o
        let mode = mode-best $o.availableModes
        let width = $mode | split row x | first | into int
        {
            x: ($acc.x + ($width / $scale | math round))
            rows: ($acc.rows | append {output: $o.name, mode: $mode, position: $"($acc.x)x0", scale: $scale})
        }
    } | get rows
}

def main-pick [monitors: list<record>]: nothing -> any {
    let internal = $monitors | where output =~ $INTERNAL_PANEL
    if ($internal | is-not-empty) { return $internal.0.output }
    let sized = $monitors | each {|m|
        let size = $m.mode | parse --regex '(?<w>\d+)x(?<h>\d+)' | into int w h | first
        {output: $m.output, area: ($size.w * $size.h)}
    }
    if ($sized | is-empty) { return null }
    $sized | where area == ($sized.area | math max) | first | get output
}

def workspaces-split [outputs: list<string>, main: any]: nothing -> record {
    if ($outputs | length) < 2 { return {} }
    let others = $outputs | where $it != $main
    let on_main = $WORKSPACE_COUNT / ($outputs | length) | math ceil
    let per_other = ($WORKSPACE_COUNT - $on_main) / ($others | length) | math ceil
    1..$WORKSPACE_COUNT | each {|ws|
        let output = if $ws <= $on_main { $main } else { $others | get (($ws - $on_main - 1) // $per_other) }
        {ws: ($ws | into string), output: $output}
    } | reduce --fold {} {|w, acc| $acc | insert $w.ws $w.output }
}

def keyboard-detect []: nothing -> record {
    if not ($KEYBOARD_CONF | path exists) { return {} }
    let conf = open --raw $KEYBOARD_CONF
    [[key xkb]; [kb_layout XkbLayout] [kb_variant XkbVariant] [kb_options XkbOptions]]
    | each {|f| {key: $f.key, value: ($conf | parse --regex ('"' + $f.xkb + '"\s+"(?<v>[^"]*)"') | get --optional 0.v)} }
    | where value != null | reduce --fold {} {|f, acc| $acc | insert $f.key $f.value }
}

export def detect [cfg: record]: nothing -> record {
    let monitors = monitors-detect
    let main = main-pick $monitors
    let scale = $monitors | where output == $main | get --optional 0.scale
    {
        monitors: $monitors
        main_monitor: $main
        workspaces: (workspaces-split ($monitors | each { $in.output }) $main)
        xwayland_scale: (if $scale == null { display-xwayland-scale $env.FORM_FACTOR } else { [1 ($scale | math round | into int)] | math max })
    } | merge (keyboard-detect)
}

def lua-from [value: any]: nothing -> string {
    match ($value | describe | split row "<" | first) {
        "nothing" => "nil"
        "string" => ($value | to json)
        "record" => $"{ ($value | items {|k, v| $'[($k | to json)] = (lua-from $v)' } | str join ', ') }"
        "list" | "table" => $"{ ($value | each { lua-from $in } | str join ', ') }"
        _ => ($value | into string)
    }
}

def platform-lua [cfg: record]: nothing -> string {
    let backlight = glob /sys/class/leds/*kbd_backlight* | get --optional 0 | if $in == null { null } else { $in | path basename }
    let facts = {
        form_factor: $env.FORM_FACTOR
        laptop: ($env.FORM_FACTOR == laptop)
        xwayland_scale: ($cfg.xwayland_scale | default (display-xwayland-scale $env.FORM_FACTOR) | into string)
        main_monitor: $cfg.main_monitor
        monitors: ($cfg.monitors | default [])
        workspaces: ($cfg.workspaces | default {})
        app_workspaces: $cfg.app_workspaces
        keyboard: {layout: ($cfg.kb_layout | default us), variant: ($cfg.kb_variant | default ""), options: ($cfg.kb_options | default "")}
        pointer: {sensitivity: $cfg.pointer_sensitivity, natural_scroll: $cfg.natural_scroll}
        kbd_backlight: $backlight
    }
    $"return (lua-from $facts)\n"
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    [
        (files-into $dir ...$LUA)
        (glob shaders/* | each {|f| file-copy $f ($dir | path join shaders ($f | path basename)) })
        ($COMMANDS | each {|f| file-copy $f ($dir | path join $f) --mode 755 })
        (file-render hypridle.conf ($dir | path join hypridle.conf) {
            DIM_S: $cfg.idle_dim_s LOCK_S: $cfg.idle_lock_s DPMS_S: $cfg.idle_dpms_s
            SUSPEND_S: $cfg.idle_suspend_s SUSPEND_SAVER_S: $cfg.idle_suspend_saver_s
        })
        (file-text ($dir | path join platform.lua) (platform-lua $cfg) --generated)
        (step reload)
    ]
}

# a config write reloads hyprland, dropping the runtime monitor layout and shader; the shader goes last, a scale
# re-render after it would drop it again
export def reload []: nothing -> nothing {
    if ($env.HYPRLAND_INSTANCE_SIGNATURE? | is-empty) { return }
    let toggles = $env.DOTFILES | path join scripts toggles
    ^hyprctl reload config-only
    ^($toggles | path join toggle-monitor-scale.nu) reapply
    ^($toggles | path join toggle-shader.nu) reapply
}

export def theme [cfg: record, wallpaper: string] {
    step reload
}
