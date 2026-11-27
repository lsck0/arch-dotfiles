use module.nu *

export const meta = {
    deps: [desktop/hyprland]
    packages: {pacman: [cava imagemagick libqalculate pipewire-audio python-gobject qrencode qt6-shadertools quickshell udisks2 websocat wtype zenity]}
}

# what the bar options' entries name: plugins/bar/widgets/<name>.qml, BarSection aside (bar.test.nu)
export const BAR_WIDGETS = [
    Agents AppMenu AudioIO Clock Discord Display Drives Exit Fluxer Homelab Indicators KeyboardLayout Media Network
    Notifications Obs Phone Separator Submap System Tray Weather Workspaces
]

export const options = {
    pomodoro_focus_min: {type: int, default: 25, doc: "Minutes of one focus block", label: "Focus", group: pomodoro, min: 1, max: 180, apply: live, scope: user}
    pomodoro_break_min: {type: int, default: 5, doc: "Minutes of the short break after a focus block", label: "Break", group: pomodoro, min: 1, max: 60, apply: live, scope: user}
    pomodoro_long_break_min: {type: int, default: 15, doc: "Minutes of the long break after the last focus block of a round", label: "Long break", group: pomodoro, min: 1, max: 120, apply: live, scope: user}
    pomodoro_cycles: {type: int, default: 4, doc: "Focus blocks before a long break", label: "Cycles", group: pomodoro, min: 1, max: 12, apply: live, scope: user}
    clipboard_history_max_age_h: {type: int, default: 12, doc: "Hours a copied text or image stays in the clipboard history", label: "Keep history for", group: clipboard, min: 1, max: 168, apply: live, scope: user}
    bar_left: {type: list<string>, default: [AppMenu Workspaces Submap], doc: "Widgets on the left of the main bar, by plugins/bar/widgets name", label: "Left", group: bar, choices: $BAR_WIDGETS, ordered: true, apply: live, scope: user}
    bar_center: {type: list<string>, default: [Clock Weather Media Obs Discord Fluxer], doc: "Widgets in the middle of the main bar", label: "Center", group: bar, choices: $BAR_WIDGETS, ordered: true, apply: live, scope: user}
    bar_right: {
        type: list<string>
        default: [Tray Separator Agents Phone Homelab System Drives Network Display AudioIO Notifications KeyboardLayout Indicators Exit]
        doc: "Widgets on the right of the main bar"
        label: "Right"
        group: bar
        choices: $BAR_WIDGETS
        ordered: true
        apply: live
        scope: user
    }
    bar_secondary_left: {type: list<string>, default: [AppMenu Workspaces Submap], doc: "Widgets on the left of every other screen's bar", label: "Other screens left", group: bar, choices: $BAR_WIDGETS, ordered: true, apply: live, scope: user}
    bar_secondary_center: {type: list<string>, default: [], doc: "Widgets in the middle of every other screen's bar", label: "Other screens center", group: bar, choices: $BAR_WIDGETS, ordered: true, apply: live, scope: user}
    bar_secondary_right: {type: list<string>, default: [], doc: "Widgets on the right of every other screen's bar", label: "Other screens right", group: bar, choices: $BAR_WIDGETS, ordered: true, apply: live, scope: user}
    notification_low_s: {type: int, default: 5, doc: "Seconds a low urgency popup stays at least", label: "Low popup", group: notifications, min: 1, max: 120, apply: live, scope: user}
    notification_normal_s: {type: int, default: 8, doc: "Seconds a normal popup stays at least; critical ones stay until dismissed", label: "Normal popup", group: notifications, min: 1, max: 120, apply: live, scope: user}
    notification_max_s: {type: int, default: 30, doc: "Seconds a popup stays at most, whatever its sender asks", label: "Popup at most", group: notifications, min: 1, max: 600, apply: live, scope: user}
    notification_history_max: {type: int, default: 30, doc: "Notifications kept in the history", label: "History", group: notifications, min: 1, max: 500, apply: live, scope: user}
    fx_glow: {type: float, default: 0.22, doc: "Accent glow around text and edges", label: "Glow", group: effects, min: 0.0, max: 1.0, step: 0.01, apply: live, scope: user}
    fx_scanlines: {type: float, default: 0.06, doc: "Opacity of the scanline overlay", label: "Scanlines", group: effects, min: 0.0, max: 0.3, step: 0.01, apply: live, scope: user}
    fx_flicker: {type: float, default: 0.02, doc: "CRT brightness flicker", label: "Flicker", group: effects, min: 0.0, max: 0.1, step: 0.01, apply: live, scope: user}
    fx_matrix_rain: {type: float, default: 0.5, doc: "Glyph rain on the lock screen", label: "Matrix rain", group: effects, min: 0.0, max: 1.0, step: 0.05, apply: live, scope: user}
    fx_corner_brackets: {type: bool, default: true, doc: "Corner brackets on panels and cards", label: "Corner brackets", group: effects, apply: live, scope: user}
    fx_motion: {type: bool, default: true, doc: "Shell animations: glitch, shake, reveals, typing; off as under the power saver", label: "Motion", group: effects, apply: live, scope: user}
    fx_glitch: {type: bool, default: true, doc: "Glitch flash on lock, unlock and launch", label: "Glitch", group: effects, apply: live, scope: user}
    desktop_quote: {type: bool, default: true, doc: "Daily quote on the wallpaper", label: "Quote", group: desktop, apply: live, scope: user}
    desktop_quotes_file: {type: string?, default: null, doc: "JSON list of {text, author} to draw the daily quote from instead of the built-in one", label: "Quotes file", group: desktop, apply: live, scope: user}
    desktop_agenda: {type: bool, default: true, doc: "Tasks, reminders, events and the pomodoro on the wallpaper", label: "Agenda", group: desktop, apply: live, scope: user}
    desktop_blur: {type: bool, default: false, doc: "Blur the agenda and notes on the wallpaper past reading, as while streaming or recording", label: "Blur agenda and notes", group: desktop, apply: live, scope: user}
    lock_show_media: {type: bool, default: true, doc: "Playing track on the lock screen", label: "Media", group: lock, apply: live, scope: user}
    lock_show_notifications: {type: bool, default: true, doc: "Unread notifications on the lock screen", label: "Notifications", group: lock, apply: live, scope: user}
    sounds: {type: bool, default: true, doc: "Chimes for alerts, reminders and pomodoro phases", label: "Sounds", group: notifications, apply: live, scope: user}
    notification_position: {type: string, default: right, doc: "Corner of the screen popups stack in, below the bar", label: "Popup corner", group: notifications, choices: [right left], apply: live, scope: user}
    weather_units: {type: string, default: metric, doc: "Units of the weather widget", label: "Units", group: weather, choices: [metric imperial], apply: live, scope: user}
    weather_location_sources: {
        type: list<string>
        default: [geoclue timezone ipgeo]
        doc: "Where weather looks for the location, in order, when none is pinned; geoclue and ipgeo ask online services"
        label: "Location sources"
        group: weather
        choices: [geoclue timezone ipgeo]
        apply: live
        scope: user
    }
    clock_zones: {
        type: list<string>
        default: ["NA West=America/Los_Angeles" "NA Central=America/Chicago" "NA East=America/New_York" "UK=Europe/London" "Central EU=Europe/Berlin" "NZ=Pacific/Auckland" "JP=Asia/Tokyo"]
        doc: "World clocks in the clock panel: an IANA zone, or label=zone"
        label: "World clocks"
        group: clock
        apply: live
        scope: user
    }
    bar_spectrum: {type: bool, default: true, doc: "Audio spectrum behind the bar's media widget", label: "Media spectrum", group: bar, apply: live, scope: user}
    tray_default: {
        type: string
        default: drawer
        doc: "Where a tray icon sits until it is pinned, hidden or put back by hand: the drawer, pinned, or hidden"
        label: "Tray icons"
        group: bar
        choices: [drawer pinned hidden]
        apply: live
        scope: user
    }
    agent_usage_limits: {type: bool, default: true, doc: "Rate-limit bars in the agents widget; each refresh sends a one-token request on your Claude plan", label: "Agent limits", group: bar, apply: live, scope: user}
}

const CONFIG_DIR = ".config/quickshell"
const SKIP = [mod.nu AGENTS.md .qmllint.ini .gitignore dotfiles-settings.desktop theme.json]
const SKIP_PATTERN = '(__pycache__|\.log$|\.qsb$|\.test\.(nu|sh)$)'
const UNIT = "quickshell.service"
# files that define types: hot reload fails on one the running shell never loaded ("<Name> is not a type")
const TYPE_EXTENSIONS = [qml js]
const TYPE_FILES = [qmldir]

def pomodoro-config [cfg: record]: nothing -> record {
    let config = {focus: $cfg.pomodoro_focus_min, break: $cfg.pomodoro_break_min, long: $cfg.pomodoro_long_break_min, cycles: $cfg.pomodoro_cycles}
    file-text ($nu.home-dir | path join $CONFIG_DIR pomodoro.json) $"($config | to json --raw)\n" --generated
}

def clipboard-config [cfg: record]: nothing -> record {
    file-text ($nu.home-dir | path join $CONFIG_DIR clipboard.json) $"({max_age_h: $cfg.clipboard_history_max_age_h} | to json --raw)\n" --generated
}

def bar-config [cfg: record]: nothing -> record {
    let config = {
        bar: {left: $cfg.bar_left, center: $cfg.bar_center, right: $cfg.bar_right}
        barSecondary: {left: $cfg.bar_secondary_left, center: $cfg.bar_secondary_center, right: $cfg.bar_secondary_right}
    }
    file-text ($nu.home-dir | path join $CONFIG_DIR bar.json) $"($config | to json --raw)\n" --generated
}

def notify-config [cfg: record]: nothing -> record {
    let config = {low_s: $cfg.notification_low_s, normal_s: $cfg.notification_normal_s, max_s: $cfg.notification_max_s, history: $cfg.notification_history_max}
    file-text ($nu.home-dir | path join $CONFIG_DIR notify.json) $"($config | to json --raw)\n" --generated
}

# the shell's other options in one file: QML reads it through the Prefs singleton, the nu helpers open it
def prefs-config [cfg: record]: nothing -> record {
    let config = {
        motion: $cfg.fx_motion
        glitch: $cfg.fx_glitch
        desktopQuote: $cfg.desktop_quote
        desktopQuotesFile: $cfg.desktop_quotes_file
        desktopAgenda: $cfg.desktop_agenda
        desktopBlur: $cfg.desktop_blur
        lockMedia: $cfg.lock_show_media
        lockNotifications: $cfg.lock_show_notifications
        sounds: $cfg.sounds
        notificationPosition: $cfg.notification_position
        weatherUnits: $cfg.weather_units
        weatherSources: $cfg.weather_location_sources
        clockZones: $cfg.clock_zones
        barSpectrum: $cfg.bar_spectrum
        trayDefault: $cfg.tray_default
        agentLimits: $cfg.agent_usage_limits
    }
    file-text ($nu.home-dir | path join $CONFIG_DIR prefs.json) $"($config | to json --raw)\n" --generated
}

# the fx section in theme.json's key order; the repo copy holds the knobs that are no option
def theme-config [cfg: record]: nothing -> record {
    let theme = open config/theme.json
    let fx = {
        glowStrength: $cfg.fx_glow
        scanlineOpacity: $cfg.fx_scanlines
        ...($theme.fx | select scanlineSpacing phosphorBias)
        cornerBrackets: $cfg.fx_corner_brackets
        crtFlicker: $cfg.fx_flicker
        matrixRain: $cfg.fx_matrix_rain
    }
    file-text ($nu.home-dir | path join $CONFIG_DIR theme.json) $"($theme | update fx $fx | to json --indent 2)\n" --in-place
}

# Whether a copy defines QML types the running shell would have to load anew.
def type-file [name: string]: nothing -> bool {
    ($name | path basename) in $TYPE_FILES or ($name | path parse | get extension) in $TYPE_EXTENSIONS
}

# Whether a copy is a `.pragma library` script: the engine imports it once, so hot reload keeps its old code
def library-js [src: path]: nothing -> bool {
    ($src | path parse | get extension) == "js" and (open --raw $src | lines | first 5 | any { str trim | $in == ".pragma library" })
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let files = ls --long ...(glob --no-dir config/**/*) | update name { path relative-to ($env.PWD | path join config) }
        | where {|f| ($f.name | path basename) not-in $SKIP and $f.name !~ $SKIP_PATTERN }
    let restart = then-step shell-restart
    [
        # in place: quickshell's file watcher follows the inode, so a replaced copy can go unseen and never reload; a
        # type file new to the tree fails that reload, and a changed library script is never imported again, so both
        # restart the shell instead
        ($files | each {|f|
            let dest = $dir | path join $f.name
            let src = "config" | path join $f.name
            let then = if ((type-file $f.name) and not ($dest | path exists)) or (library-js $src) { $restart } else { [] }
            file-copy $src $dest --in-place --then $then --mode (if ($f.mode | str substring 2..2) == "x" { "755" } else { "644" })
        })
        (link-commands ...(glob 'config/scripts/*.{nu,sh}' | where $it !~ $SKIP_PATTERN))
        # not enabled: hyprland_autostart.lua starts it
        (unit-file services/quickshell.service)
        (unit-file services/quickshell-reminders-rearm.service --enable)
        (pomodoro-config $cfg)
        (clipboard-config $cfg)
        (bar-config $cfg)
        (notify-config $cfg)
        (prefs-config $cfg)
        (theme-config $cfg)
        # the settings window outside hyprland (settings-only.qml), listed in Plasma's launcher only
        (file-render config/dotfiles-settings.desktop (xdg data applications dotfiles-settings.desktop) {HOME: $nu.home-dir})
    ]
}

# Restarts a running shell after a type file new to it or a changed library script landed. A dot run the shell started itself (the settings
# window's apply) sits in its cgroup and would die with it: that run only says so.
export def shell-restart []: nothing -> nothing {
    if (open --raw /proc/self/cgroup | str contains $"/($UNIT)") {
        log-note $"quickshell: new QML files or changed library scripts, its hot reload keeps the old code until restart.nu restarts ($UNIT)"
        return
    }
    if (do { ^systemctl --user is-active --quiet $UNIT } | complete).exit_code != 0 { return }
    ^systemctl --user restart $UNIT
}

export def apply [cfg: record] {
    [(pomodoro-config $cfg) (clipboard-config $cfg) (bar-config $cfg) (notify-config $cfg) (prefs-config $cfg) (theme-config $cfg)]
}
