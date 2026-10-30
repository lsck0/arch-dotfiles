# hyprland's lua config, plus platform.lua generated each run from the live monitors and keyboard

use module.nu *
use ../../core/wallust/palette.nu [RADIUS_PX BORDER_PX OPACITY_WINDOW OPACITY_SURFACE]

export const meta = {
    packages: {
        pacman: [
            app2unit bemenu-wayland brightnessctl cpio ddcutil grim hyprcursor hypridle hyprland hyprlock hyprpicker
            libnotify libx11 mission-center omarchy-share-picker-git pavucontrol playerctl polkit
            polkit-kde-agent qt5-wayland qt6-wayland rose-pine-cursor rose-pine-hyprcursor slurp wayland
            wayland-boomer-git wl-clip-persist wl-clipboard xdg-desktop-portal-gtk xdg-desktop-portal-hyprland
            xdg-desktop-portal-kde xorg-server xorg-xauth xorg-xhost xorg-xinput xorg-xwayland ydotool
        ]
    }
    # core/locale's keyboard, written by localectl: a layout change re-renders platform.lua
    inputs: [/etc/X11/xorg.conf.d/00-keyboard.conf]
}

export const options = {
    monitors: {
        type: list<record>?
        default: null
        doc: "One hl.monitor per output: output, mode, position, scale; detected from the connected outputs, any other output gets its preferred mode and an auto scale"
        group: display
    }
    main_monitor: {
        type: string?
        default: null
        doc: "The output holding workspace 1, the bar's notifications, steam's toasts and the tablet; detected: the internal panel, else the largest, leftmost on a tie"
        group: display
    }
    workspaces: {
        type: record?
        default: null
        doc: "Workspace to output; detected: the first ceil(10 / outputs) on the main monitor, the rest split over the others left to right"
        label: "Workspace layout"
        group: display
    }
    xwayland_scale: {
        type: int?
        default: null
        doc: "GDK_SCALE for X11 apps (force_zero_scaling); detected: the main monitor's scale rounded, else 1 on a laptop and 2 elsewhere"
        label: "XWayland scale"
        group: display
        min: 1
        max: 4
    }
    app_workspaces: {
        type: list<record>
        default: []
        doc: "Homes for apps by window class: {class, workspace, silent}; silent opens them without switching to their workspace or focusing them"
        group: display
        scope: user
    }
    pointer_sensitivity: {
        type: float
        default: 0.0
        doc: "libinput pointer acceleration, -1 to 1"
        group: input
        min: -1.0
        max: 1.0
        step: 0.05
        scope: user
    }
    natural_scroll: {
        type: bool
        default: false
        doc: "Touchpad content follows the fingers"
        label: "Natural scrolling"
        group: input
        scope: user
    }
    idle_dim_s: {type: int, default: 900, doc: "Idle seconds until the screens dim", label: "Dim after", group: idle, min: 60, apply: relogin, scope: user}
    idle_lock_s: {type: int, default: 1200, doc: "Idle seconds until the session locks", label: "Lock after", group: idle, min: 60, apply: relogin, scope: user}
    idle_dpms_s: {type: int, default: 2100, doc: "Idle seconds until the screens go off", label: "Screens off after", group: idle, min: 60, apply: relogin, scope: user}
    idle_suspend_s: {type: int, default: 2400, doc: "Idle seconds until suspend, unless an agent works or an inhibitor holds", label: "Suspend after", group: idle, min: 60, apply: relogin, scope: user}
    idle_dim_saver_s: {type: int, default: 300, doc: "Idle seconds until the screens dim in power saver (a laptop on battery)", label: "Dim in power saver after", group: idle, min: 60, apply: relogin, scope: user}
    idle_lock_saver_s: {type: int, default: 600, doc: "Idle seconds until the session locks in power saver", label: "Lock in power saver after", group: idle, min: 60, apply: relogin, scope: user}
    idle_suspend_saver_s: {type: int, default: 1800, doc: "Idle seconds until suspend in power saver", label: "Suspend in power saver after", group: idle, min: 60, apply: relogin, scope: user}
}

const CONFIG_DIR = ".config/hypr"
const CONFIG_FILES = [
    hyprland.lua hyprland_autostart.lua hyprland_cursor.lua hyprland_input.lua hyprland_keybindings.lua
    hyprland_layout.lua hyprland_misc.lua hyprland_monitors.lua hyprland_plugins.lua hyprland_powersave.lua
    hyprland_windowrules.lua hyprland_windows.lua wal_colors.lua hyprlock.conf xdph.conf
]
const COMMANDS = [lockscreen-stats.nu quickshell-lock-launch.nu screen-dim.nu]
const KEYBOARD_CONF = "/etc/X11/xorg.conf.d/00-keyboard.conf"
const INTERNAL_PANEL = '^(eDP|LVDS|DSI)-'
const WORKSPACE_COUNT = 10
const TARGET_DPI = {laptop: 150.0, desktop: 110.0}
const MM_PER_INCH = 25.4
const SCALES = [1.0 1.25 1.5 1.666667 2.0 2.5 3.0]

# Whether this process's Hyprland still runs: a shell started under one keeps its signature after a logout.
def hyprland-live []: nothing -> bool {
    let sig = $env.HYPRLAND_INSTANCE_SIGNATURE? | default ""
    $sig != "" and ($env.XDG_RUNTIME_DIR? | default "" | path join hypr $sig .socket.sock | path exists)
}

def outputs-live []: nothing -> table {
    if not (hyprland-live) { return [] }
    # disabled outputs too: a docked closed lid turns the panel off, and it must stay the layout's main
    try { ^hyprctl -j monitors all | from json } catch { [] } | where name !~ '^HEADLESS-' | sort-by x
}

def mode-best [modes: list<string>]: nothing -> string {
    let best = $modes | parse --regex '(?<w>\d+)x(?<h>\d+)@(?<hz>[\d.]+)Hz' | into int w h | into float hz
        | sort-by --reverse {|m| [($m.w * $m.h) $m.hz] } | first
    if $best == null { "preferred" } else { $"($best.w)x($best.h)@($best.hz | math round)" }
}

def scale-for [output: record, width: int]: nothing -> float {
    if $output.physicalWidth <= 0 { return 1.0 }
    let target = if $env.FORM_FACTOR == laptop { $TARGET_DPI.laptop } else { $TARGET_DPI.desktop }
    let wanted = $width / ($output.physicalWidth / $MM_PER_INCH) / $target
    $SCALES | sort-by {|s| $s - $wanted | math abs } | first
}

def monitors-detect []: nothing -> list<record> {
    outputs-live | reduce --fold {x: 0, rows: []} {|o, acc|
        let mode = mode-best $o.availableModes
        let width = if $mode == "preferred" { $o.width? | default 1920 } else { $mode | split row x | first | into int }
        let scale = scale-for $o $width
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
        let size = $m.mode | parse --regex '(?<w>\d+)x(?<h>\d+)' | into int w h | get --optional 0 | default {w: 0, h: 0}
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

# the layout core/locale set through localectl: that module owns it, the compositor only follows
def keyboard-read []: nothing -> record {
    let conf = if ($KEYBOARD_CONF | path exists) { open --raw $KEYBOARD_CONF } else { "" }
    let field = {|xkb| $conf | parse --regex ('"' + $xkb + '"\s+"(?<v>[^"]*)"') | get --optional 0.v }
    {
        layout: (do $field XkbLayout | default us)
        variant: (do $field XkbVariant | default "")
        options: (do $field XkbOptions | default "")
    }
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

def xwayland-scale [scale: any]: nothing -> int {
    if $scale == null { display-xwayland-scale $env.FORM_FACTOR } else { [1 ($scale | math round | into int)] | math max }
}

export def detect [cfg: record]: nothing -> record {
    let monitors = monitors-detect
    let main = main-pick $monitors
    {
        monitors: $monitors
        main_monitor: $main
        workspaces: (workspaces-split ($monitors | each { $in.output }) $main)
        xwayland_scale: (xwayland-scale ($monitors | where output == $main | get --optional 0.scale))
    }
}

# Detect sees no output outside hyprland: picks over the platform's monitors keep platform.lua stable.
def platform-lua [cfg: record]: nothing -> string {
    let backlight = glob /sys/class/leds/*kbd_backlight* | get --optional 0 | if $in == null { null } else { $in | path basename }
    let monitors = $cfg.monitors | default []
    let main = $cfg.main_monitor | default (main-pick $monitors)
    let facts = {
        form_factor: $env.FORM_FACTOR
        laptop: ($env.FORM_FACTOR == laptop)
        xwayland_scale: ($cfg.xwayland_scale | default (xwayland-scale ($monitors | where output == $main | get --optional 0.scale)) | into string)
        main_monitor: $main
        monitors: $monitors
        workspaces: ($cfg.workspaces | default (workspaces-split ($monitors | each { $in.output }) $main))
        app_workspaces: $cfg.app_workspaces
        keyboard: (keyboard-read)
        pointer: {sensitivity: $cfg.pointer_sensitivity, natural_scroll: $cfg.natural_scroll}
        kbd_backlight: $backlight
    }
    $"return (lua-from $facts)\n"
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    [
        (files-into $dir ...$CONFIG_FILES)
        (glob shaders/* | each {|f| file-copy $f ($dir | path join shaders ($f | path basename)) })
        ($COMMANDS | each {|f| file-copy $f ($dir | path join $f) --mode 755 })
        (file-render hypridle.conf ($dir | path join hypridle.conf) {
            DIM_S: $cfg.idle_dim_s LOCK_S: $cfg.idle_lock_s DPMS_S: $cfg.idle_dpms_s
            SUSPEND_S: $cfg.idle_suspend_s DIM_SAVER_S: $cfg.idle_dim_saver_s LOCK_SAVER_S: $cfg.idle_lock_saver_s
            SUSPEND_SAVER_S: $cfg.idle_suspend_saver_s
        })
        (unit-enable hypridle.service --now)
        (file-text ($dir | path join platform.lua) (platform-lua $cfg) --generated)
        (file-text ($dir | path join style.lua) $"return (lua-from {rounding: $RADIUS_PX, border: $BORDER_PX, opacity: $OPACITY_WINDOW, opacity_surface: $OPACITY_SURFACE})\n" --generated)
        (step plugins-build)
        (step reload)
    ]
}

export def plugins-build []: nothing -> nothing {
    ^($env.DOTFILES | path join configs desktop hyprland plugins.nu)
}

export def update [cfg: record]: nothing -> nothing { plugins-build }

# Reloads hyprland; the shader goes last, a config write or scale re-render after it drops it.
export def reload []: nothing -> nothing {
    if not (hyprland-live) { return }
    let toggles = $env.DOTFILES | path join scripts toggles
    ^hyprctl reload config-only
    ^($toggles | path join toggle-monitor-scale.nu) reapply
    ^($toggles | path join toggle-shader.nu) reapply
}

export def theme [cfg: record, wallpaper: string] {
    step reload
}
