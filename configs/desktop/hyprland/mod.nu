# hyprland's lua config, plus platform.lua generated each run from the live monitors and keyboard

use module.nu *
use ../../core/wallust/scripts/palette.nu [
    RADIUS_PX BORDER_PX OPACITY_WINDOW SHADE_CHROME SHADE_CURRENT SHADE_HOVER is-light palette-rgb readable-on shade rgb-to-hex
]
use ../../core/wallust/scripts/font.nu [font-load]
use scripts/plugins.nu [plugins-missing plugins-unloaded]
use scripts/reload.nu [hyprland-reload]
use ../cursor/scripts/size.nu [cursor-size]

export const meta = {
    deps: [base/essentials]
    # SUPER+a, e and n start base/xdg's first browser, file manager and editor; desktop/cursor's size and
    # desktop/shimoji's enable reach platform.lua
    # core/locale: a keyboard change through dot set re-links this module, after root's localectl rewrote the X11 file
    # platform.lua follows; without it the compositor kept the old layout until the next whole dot apply
    reads: [base/xdg core/locale desktop/cursor desktop/shimoji]
    packages: {
        pacman: [
            app2unit bemenu-wayland brightnessctl ddcutil grim hyprcursor hypridle hyprland hyprlock hyprpicker
            libnotify mission-center omarchy-share-picker-git pavucontrol playerctl polkit
            qt5-wayland qt6-wayland slurp wayland
            wayland-boomer-git wl-clip-persist wl-clipboard xdg-desktop-portal-gtk xdg-desktop-portal-hyprland
            xdg-desktop-portal-kde xorg-xhost xorg-xrdb xorg-xwayland ydotool
        ]
    }
    # core/locale's keyboard, written by localectl: a layout change re-renders platform.lua; the applications dirs'
    # mtimes: an app installed or removed changes which default app a key starts
    inputs: [/etc/X11/xorg.conf.d/00-keyboard.conf /usr/share/applications ~/.local/share/applications]
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
    bind_workspaces: {
        type: bool
        default: true
        doc: "Each workspace lives on its own monitor (the layout below); off, a workspace opens on the focused monitor"
        label: "Bind workspaces to monitors"
        group: display
        scope: user
    }
    workspaces: {
        type: record?
        default: null
        doc: "Workspace to output; unset: the first ceil(10 / outputs) on the main monitor, the rest split over the others left to right"
        label: "Workspace layout"
        group: display
    }
    xwayland_scale: {
        type: int?
        default: null
        doc: "GDK_SCALE for X11 apps (force_zero_scaling); unset: the main monitor's scale rounded, else 1 on a laptop and 2 elsewhere"
        label: "XWayland scale"
        group: display
        min: 1
        max: 4
    }
    app_workspaces: {
        type: list<record>
        default: []
        doc: ("Homes for apps by window class: {class, workspace, silent, tabbed?}; silent opens them without switching to their "
            + "workspace or focusing them; the tabbed homes of one workspace open as one tab group")
        group: display
        scope: user
    }
    lock_screen: {
        type: string
        default: quickshell
        choices: [quickshell hyprlock]
        doc: "The lock screen hypridle and every lock key start; the other is the fallback"
        label: "Lock screen"
        group: idle
        scope: machine
    }
    monitor_speaker_volume: {
        type: int?
        default: null
        doc: "Every DDC monitor's built-in speaker volume (VCP 0x62), set at session start; 0 silences speakers fed by DisplayPort audio, which can pop on wake"
        label: "Monitor speaker volume"
        group: display
        min: 0
        max: 100
        scope: machine
        apply: relogin
    }
    autostart: {
        type: list<record>
        default: []
        doc: "Apps started once per login: {cmd, workspace?, float?, after?}; workspace and float apply to the window the command's own process opens; after names a window class whose first window starts this one (an order on a shared workspace)"
        label: "Autostart"
        group: session
        scope: user
        apply: relogin
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
    left_handed: {type: bool, default: false, doc: "Swaps the primary and secondary mouse buttons", label: "Left-handed", group: input, scope: user}
    accel_profile: {
        type: string
        default: default
        choices: [default adaptive flat]
        doc: "Pointer acceleration; flat turns it off, default is libinput's per device"
        label: "Pointer acceleration"
        group: input
        scope: user
    }
    focus_follows_mouse: {type: bool, default: true, doc: "Focus moves to the window under the pointer; off, a click focuses", label: "Focus follows mouse", group: input, scope: user}
    cursor_shake: {
        type: bool
        default: true
        doc: "Shaking the pointer enlarges it (the dynamic-cursors plugin); off, the plugin is neither built nor loaded"
        label: "Shake to find cursor"
        group: input
        scope: user
        apply: relogin
    }
    repeat_rate_hz: {type: int, default: 30, doc: "Key repeats per second while held", label: "Key repeat rate", group: input, min: 1, max: 100, scope: user}
    repeat_delay_ms: {type: int, default: 400, doc: "Hold time before a key repeats", label: "Key repeat delay", group: input, min: 100, max: 2000, step: 50, scope: user}
    numlock: {type: bool, default: true, doc: "Num lock on at login", label: "Num lock", group: input, scope: user}
    tap_to_click: {type: bool, default: true, doc: "A touchpad tap clicks", label: "Tap to click", group: input, scope: user}
    touchpad_scroll_factor: {type: float, default: 0.5, doc: "Touchpad scroll distance multiplier", label: "Touchpad scroll speed", group: input, min: 0.1, max: 3.0, step: 0.05, scope: user}
    cursor_hide_s: {type: int, default: 10, doc: "Idle seconds until the cursor hides, 0 never", label: "Hide cursor after", group: input, min: 0, max: 600, scope: user}
    gaps_in_px: {type: int, default: 4, doc: "Gap between tiled windows", label: "Inner gaps", group: layout, min: 0, max: 64, scope: user}
    border_px: {type: int, default: $BORDER_PX, doc: "Window border width, the focused window's in the accent gradient", label: "Border width", group: layout, min: 0, max: 16, scope: user}
    gaps_out_px: {type: int, default: 8, doc: "Gap between tiled windows and the screen edge", label: "Outer gaps", group: layout, min: 0, max: 64, scope: user}
    blur: {
        type: bool
        default: true
        doc: "Blur behind translucent windows (terminals, editors); off with Blur menus on, only the shell and menus blur"
        label: "Blur"
        group: layout
        scope: user
    }
    blur_menus: {
        type: bool
        default: true
        doc: ("Blur the screen behind an open shell card (its dimmed backdrop), popups and untitled floating X11 windows "
            + "(menus, tooltips), apart from Blur; off, the shell's own surfaces keep their glass while Blur is on")
        label: "Blur menus"
        group: layout
        scope: user
    }
    window_opacity: {
        type: float
        default: $OPACITY_WINDOW
        doc: ("Opacity of the apps faded whole, text included (Discord, Fluxer, Spotify, the file managers); below the "
            + "default their dimmed text can drop under 3:1 over a bright wallpaper")
        label: "Window opacity"
        group: layout
        min: 0.3
        max: 1.0
        step: 0.05
        scope: user
    }
    shadows: {type: bool, default: true, doc: "Drop shadows under windows", label: "Shadows", group: layout, scope: user}
    animations: {type: bool, default: true, doc: "Window, layer and workspace animations; power saver turns them off regardless", label: "Animations", group: layout, scope: user}
    vrr: {
        type: string
        default: off
        choices: [off on fullscreen fullscreen_games]
        doc: "Adaptive sync; fullscreen_games: fullscreen video and game windows only"
        label: "Variable refresh rate"
        group: display
    }
    idle_dim_s: {type: int, default: 900, doc: "Idle seconds until the screens dim", label: "Dim after", group: idle, min: 60, scope: user}
    idle_lock_s: {type: int, default: 1200, doc: "Idle seconds until the session locks", label: "Lock after", group: idle, min: 60, scope: user}
    idle_dpms_s: {type: int, default: 2100, doc: "Idle seconds until the screens go off", label: "Screens off after", group: idle, min: 60, scope: user}
    idle_suspend: {type: bool, default: true, doc: "Suspend after the idle times below; off, idle never suspends", label: "Suspend when idle", group: idle, scope: user}
    idle_dim_monitors: {type: bool, default: true, doc: "Idle dim also lowers external monitors over DDC/CI; off, only the panel backlight and keyboard light dim", label: "Dim external monitors", group: idle, scope: machine}
    idle_suspend_s: {type: int, default: 2400, doc: "Idle seconds until suspend, unless an agent works or an inhibitor holds", label: "Suspend after", group: idle, min: 60, scope: user}
    idle_dim_saver_s: {type: int, default: 300, doc: "Idle seconds until the screens dim in power saver (a laptop on battery)", label: "Dim in power saver after", group: idle, min: 60, scope: user}
    idle_lock_saver_s: {type: int, default: 600, doc: "Idle seconds until the session locks in power saver", label: "Lock in power saver after", group: idle, min: 60, scope: user}
    idle_dpms_saver_s: {type: int, default: 660, doc: "Idle seconds until the screens go off in power saver", label: "Screens off in power saver after", group: idle, min: 60, scope: user}
    idle_suspend_saver_s: {type: int, default: 1800, doc: "Idle seconds until suspend in power saver", label: "Suspend in power saver after", group: idle, min: 60, scope: user}
    screen_shader: {
        type: string?
        default: null
        doc: "Shader each login starts with, a toggle-shader.nu list name (colorblind-correction:deuteranopia)"
        label: "Screen shader at login"
        group: display
        scope: user
        apply: relogin
    }
}

const CONFIG_DIR = ".config/hypr"
const SHARE_PICKER_COLORS = ".local/state/omarchy/current/theme/colors.toml"
const CONFIG_FILES = [
    hyprland.lua hyprland_autostart.lua hyprland_cursor.lua hyprland_input.lua hyprland_keybindings.lua
    hyprland_layout.lua hyprland_misc.lua hyprland_monitors.lua hyprland_plugins.lua hyprland_powersave.lua
    hyprland_windowrules.lua hyprland_windows.lua wal_colors.lua hyprlock.conf xdph.conf
]
const COMMANDS = [dpms.nu lockscreen-stats.nu quickshell-lock-launch.nu screen-dim.nu]
const KEYBOARD_CONF = "/etc/X11/xorg.conf.d/00-keyboard.conf"
const WORKSPACE_COUNT = 10
const TARGET_DPI = {laptop: 150.0, desktop: 110.0}
const MM_PER_INCH = 25.4
const SCALES = [1.0 1.25 1.5 1.666667 2.0 2.5 3.0]
# the width of an output listing no modes
const WIDTH_FALLBACK_PX = 1920
const REFRESH_FLUID_HZ = 50.0
const PLUGINS = path self scripts/plugins.nu
# input.follow_mouse: 1 focuses the window under the pointer, 2 only on a click
const FOLLOW_MOUSE = {on: 1, off: 2}
# misc.vrr's values by the vrr option's choice
const VRR_MODES = {off: 0, on: 1, fullscreen: 2, fullscreen_games: 3}
# system and flatpak desktop entries, after the user's own
const DESKTOP_DIRS = [/var/lib/flatpak/exports/share/applications /usr/local/share/applications /usr/share/applications]

# A Hyprland instance dir whose lock names a running pid; a dead one keeps its dir and socket file behind.
def instance-alive [dir: path]: nothing -> bool {
    let pid = try { open --raw ($dir | path join hyprland.lock) | lines | first | str trim } catch { "" }
    $pid != "" and (["/proc" $pid] | path join | path exists) and ($dir | path join .socket.sock | path exists)
}

# Whether a Hyprland runs for this process, adopting the live instance when the inherited signature is dead: a shell
# (a herdr pane, a ssh login) keeps the signature of the Hyprland it was started under through a crash or a relogin.
export def --env hyprland-live []: nothing -> bool {
    let hypr = xdg runtime hypr
    let sig = $env.HYPRLAND_INSTANCE_SIGNATURE? | default ""
    if $sig != "" and (instance-alive ($hypr | path join $sig)) { return true }
    let live = try { ls $hypr } catch { [] } | where type == dir and (instance-alive $it.name) | sort-by modified
        | get --optional name | default [] | last
    if $live == null { return false }
    let display = try { open --raw ($live | path join hyprland.lock) | lines | get 1 | str trim } catch { "" }
    $env.HYPRLAND_INSTANCE_SIGNATURE = $live | path basename
    if $display != "" { $env.WAYLAND_DISPLAY = $display }
    true
}

def --env outputs-live []: nothing -> table {
    if not (hyprland-live) { return [] }
    # disabled outputs too: a docked closed lid turns the panel off, and it must stay the layout's main
    monitors-live --all | sort-by x
}

# The largest mode at the highest rate, among the fluid ones when there are: a TV's 4096x2160@24 (DCI) would beat its
# 3840x2160@60 on area alone.
def mode-best [modes: list<string>]: nothing -> string {
    let parsed = $modes | parse --regex '(?<w>\d+)x(?<h>\d+)@(?<hz>[\d.]+)Hz' | into int w h | into float hz
    let fluid = $parsed | where hz >= $REFRESH_FLUID_HZ
    let best = if ($fluid | is-empty) { $parsed } else { $fluid } | sort-by --reverse {|m| [($m.w * $m.h) $m.hz] } | first
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
        let width = if $mode == "preferred" { $o.width? | default $WIDTH_FALLBACK_PX } else { $mode | split row x | first | into int }
        let scale = scale-for $o $width
        {
            x: ($acc.x + ($width / $scale | math round))
            rows: ($acc.rows | append {output: $o.name, mode: $mode, position: $"($acc.x)x0", scale: $scale})
        }
    } | get rows
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

# Only the live outputs: outside a running Hyprland (a tty, the install chain) nothing lands. The workspace split and
# X11 scale follow from the resolved monitors in platform-lua (and xwayland-scale-for), so set monitors drive them too.
export def detect [cfg: record]: nothing -> record {
    let monitors = monitors-detect
    if ($monitors | is-empty) { return {} }
    {monitors: $monitors, main_monitor: (monitors-main $monitors)}
}

# A default app's desktop entry and short name (org.kde.dolphin.desktop: dolphin): the first one installed, as xdg-open
# walks the list; none installed, no bind.
def app-default [entries: list<string>]: nothing -> any {
    let dirs = [(xdg data applications) (xdg data flatpak exports share applications) ...$DESKTOP_DIRS]
    let id = $entries | where {|e| $dirs | any {|d| $d | path join $e | path exists } } | get --optional 0
    if $id == null { return null }
    {desktop: $id, name: ($id | str replace --regex '\.desktop$' '' | split row . | last)}
}

# The resolved monitors (set, else detected; none outside a live hyprland) drive the main pick, workspace split and X11
# scale, so an apply from a tty renders what one inside the session does.
def platform-lua [cfg: record]: nothing -> string {
    let backlight = glob /sys/class/leds/*kbd_backlight* | path basename | get --optional 0
    let monitors = $cfg.monitors | default []
    let main = $cfg.main_monitor | default (monitors-main $monitors)
    let xdg = $cfg.deps."base/xdg"
    let facts = {
        xwayland_scale: ($cfg.xwayland_scale | default (monitors-xwayland-scale $monitors $main $env.FORM_FACTOR) | into string)
        main_monitor: $main
        monitors: $monitors
        workspaces: (if $cfg.bind_workspaces { $cfg.workspaces | default (workspaces-split ($monitors | each { $in.output }) $main) } else { {} })
        app_workspaces: $cfg.app_workspaces
        autostart: $cfg.autostart
        monitor_speaker_volume: $cfg.monitor_speaker_volume
        keyboard: (keyboard-read)
        pointer: {
            sensitivity: $cfg.pointer_sensitivity, natural_scroll: $cfg.natural_scroll, left_handed: $cfg.left_handed
            # null leaves the key out: hyprland refuses "" and libinput then picks its own profile
            accel_profile: (if $cfg.accel_profile == default { null } else { $cfg.accel_profile })
            follow_mouse: (if $cfg.focus_follows_mouse { $FOLLOW_MOUSE.on } else { $FOLLOW_MOUSE.off })
        }
        cursor: {shake: $cfg.cursor_shake, size: (cursor-size $cfg.deps?."desktop/cursor"?)}
        mascots: ($cfg.deps?."desktop/shimoji"?.enable? | default false)
        input: {
            repeat_rate: $cfg.repeat_rate_hz, repeat_delay: $cfg.repeat_delay_ms, numlock: $cfg.numlock
            tap_to_click: $cfg.tap_to_click, scroll_factor: $cfg.touchpad_scroll_factor, cursor_hide_s: $cfg.cursor_hide_s
        }
        look: {gaps_in: $cfg.gaps_in_px, gaps_out: $cfg.gaps_out_px, blur: $cfg.blur, blur_menus: $cfg.blur_menus, shadows: $cfg.shadows, animations: $cfg.animations}
        vrr: ($VRR_MODES | get $cfg.vrr)
        apps: {browser: (app-default $xdg.browser), file_manager: (app-default $xdg.file_manager), editor: (app-default $xdg.editor)}
        kbd_backlight: $backlight
    }
    $"return (lua-from $facts)\n"
}

# the blurred backdrop is dimmed under a dark theme's light text and lifted under a light theme's dark text
const BLUR_BRIGHTNESS = {dark: 0.75, light: 1.3}

# Tab strip and title bars: the theme's background, the focused tab one shade off, text raised to TEXT_RATIO on each.
def bar-colors []: nothing -> record {
    let p = palette-rgb "hyprland bars"
    if $p == null { return {} }
    let active = $p.bg | shade $SHADE_HOVER
    let hex = {|c| $c | rgb-to-hex | $"rgb\(($in)\)" }
    {
        bar_bg: (do $hex $p.bg), bar_text: (do $hex ($p.fg | readable-on $p.bg))
        tab_active_bg: (do $hex $active), tab_active_text: (do $hex ($p.fg | readable-on $active))
        blur_brightness: (if ($p.bg | is-light) { $BLUR_BRIGHTNESS.light } else { $BLUR_BRIGHTNESS.dark })
    }
}

def style-record [cfg: record]: nothing -> record {
    let font = font-load
    {
        rounding: $RADIUS_PX, border: $cfg.border_px, opacity_window: $cfg.window_opacity
        font: $font.family, font_size: $font.ui_size
    } | merge (bar-colors)
}

# hypridle.conf with the idle times; without idle_suspend the suspend listeners go, without idle_dim_monitors the dim
# leaves DDC/CI monitors alone.
def hypridle-conf [cfg: record]: nothing -> string {
    let text = open --raw config/hypridle.conf | text-render {
        DIM_S: $cfg.idle_dim_s LOCK_S: $cfg.idle_lock_s DPMS_S: $cfg.idle_dpms_s
        SUSPEND_S: $cfg.idle_suspend_s DIM_SAVER_S: $cfg.idle_dim_saver_s LOCK_SAVER_S: $cfg.idle_lock_saver_s
        DPMS_SAVER_S: $cfg.idle_dpms_saver_s SUSPEND_SAVER_S: $cfg.idle_suspend_saver_s
        DIM_FLAGS: (if $cfg.idle_dim_monitors { "" } else { " --no-ddc" })
    }
    if $cfg.idle_suspend { return $text }
    $text | parse --regex '(?ms)(?<block>^listener \{\n.*?^\}\n\n?)' | get block
        | where $it =~ 'on-timeout = systemctl suspend' | reduce --fold $text {|block, acc| $acc | str replace $block "" }
        | str trim --right | $"($in)\n"
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let files = [
        (files-into $dir ...($CONFIG_FILES | each { $"config/($in)" }))
        (glob config/shaders/* | each {|f| file-copy $f ($dir | path join shaders ($f | path basename)) })
        ($COMMANDS | each {|f| file-copy $"scripts/($f)" ($dir | path join $f) --mode 755 })
        (unit-enable hypridle.service --now)
        (file-text ($dir | path join platform.lua) (platform-lua $cfg) --generated)
        # read by quickshell-lock-launch.nu on every lock
        (file-text ($dir | path join locker) $"($cfg.lock_screen)\n" --generated)
        # read by toggle-shader.nu's reapply when this login has picked none
        (if $cfg.screen_shader != null { file-text ($dir | path join shader) $"($cfg.screen_shader)\n" --generated })
    ] | decls-flatten
    # hyprland's own reload on a write drops the shader: one reload after every changed file restores it
    let reload = then-step reload
    let files = $files | each {|d| if $d.kind == file { $d | merge {then: $reload} } else { $d } }
    # hypridle never rereads its config: a restart applies new idle times, no hyprland reload needed
    let idle = file-text ($dir | path join hypridle.conf) (hypridle-conf $cfg) --then (unit-restart hypridle.service --if-running)
    let build = $cfg.cursor_shake and (plugins-missing | is-not-empty)
    let live = hyprland-live
    # its idle policy drives hyprctl and the quickshell lock, so it stays out of the plasma session
    let idle_unit = file-text (unit-dir | path join hypridle.service.d 10-hyprland.conf) (
        "[Unit]\nConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland\n"
    )
    [
        $files
        $idle
        $idle_unit
        # offline only the build waits: plugins built earlier still load
        (if $build { step plugins-build --network })
        (if $build or ($cfg.cursor_shake and $live and (plugins-unloaded | is-not-empty)) { step plugins-load })
    ]
}

export def plugins-build []: nothing -> nothing { ^$PLUGINS build }

export def plugins-load []: nothing -> nothing { ^$PLUGINS load }

export def update [cfg: record]: nothing -> nothing { if $cfg.cursor_shake { plugins-build; plugins-load } }

export def --env reload []: nothing -> nothing { if (hyprland-live) { hyprland-reload } }

# xdph's share picker: mode from the theme's light flag, its raised surfaces one shade off the background
def share-picker-colors []: nothing -> any {
    let p = palette-rgb "share picker"
    if $p == null { return null }
    let hex = {|c| $c | rgb-to-hex --prefix "#" }
    {
        mode: (if ($p.bg | is-light) { "light" } else { "dark" })
        background: (do $hex $p.bg), foreground: (do $hex $p.fg), muted: (do $hex $p.c8), accent: (do $hex $p.c4)
        lighter_background: (do $hex ($p.bg | shade $SHADE_CHROME)), selection: (do $hex ($p.bg | shade $SHADE_CURRENT))
    } | to toml
}

# style.lua carries the font and the bar colours, both theme inputs
export def theme [cfg: record, wallpaper: string] {
    let picker = share-picker-colors
    [
        (file-text ($nu.home-dir | path join $CONFIG_DIR style.lua) $"return (lua-from (style-record $cfg))\n" --generated)
        # omarchy-share-picker reads ~/.local/state literally, whatever XDG_STATE_HOME says
        (if $picker != null { file-text ($nu.home-dir | path join $SHARE_PICKER_COLORS) $picker --generated })
        (step reload)
    ]
}
