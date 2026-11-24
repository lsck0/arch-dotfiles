use module.nu *

export const meta = {
    deps: [desktop/hyprland]
    packages: {pacman: [cava imagemagick libqalculate pipewire-audio python-gobject qrencode qt6-shadertools quickshell udisks2 websocat wtype zenity]}
}

export const options = {
    pomodoro_focus_min: {type: int, default: 25, doc: "Minutes of one focus block", label: "Focus", group: pomodoro, min: 1, max: 180, apply: live, scope: user}
    pomodoro_break_min: {type: int, default: 5, doc: "Minutes of the short break after a focus block", label: "Break", group: pomodoro, min: 1, max: 60, apply: live, scope: user}
    pomodoro_long_break_min: {type: int, default: 15, doc: "Minutes of the long break after the last focus block of a round", label: "Long break", group: pomodoro, min: 1, max: 120, apply: live, scope: user}
    pomodoro_cycles: {type: int, default: 4, doc: "Focus blocks before a long break", label: "Cycles", group: pomodoro, min: 1, max: 12, apply: live, scope: user}
    clipboard_history_max_age_h: {type: int, default: 12, doc: "Hours a copied text or image stays in the clipboard history", label: "Keep history for", group: clipboard, min: 1, max: 168, apply: live, scope: user}
    bar_left: {type: list<string>, default: [AppMenu Workspaces Submap], doc: "Widgets on the left of the main bar, by plugins/bar/widgets name", label: "Left", group: bar, apply: live, scope: user}
    bar_center: {type: list<string>, default: [Clock Weather Media Obs Discord], doc: "Widgets in the middle of the main bar", label: "Center", group: bar, apply: live, scope: user}
    bar_right: {
        type: list<string>
        default: [Tray Separator Agents Phone Homelab System Drives Network Display AudioIO Notifications KeyboardLayout Indicators Exit]
        doc: "Widgets on the right of the main bar"
        label: "Right"
        group: bar
        apply: live
        scope: user
    }
    bar_secondary_left: {type: list<string>, default: [AppMenu Workspaces Submap], doc: "Widgets on the left of every other screen's bar", label: "Other screens left", group: bar, apply: live, scope: user}
    bar_secondary_center: {type: list<string>, default: [], doc: "Widgets in the middle of every other screen's bar", label: "Other screens center", group: bar, apply: live, scope: user}
    bar_secondary_right: {type: list<string>, default: [], doc: "Widgets on the right of every other screen's bar", label: "Other screens right", group: bar, apply: live, scope: user}
    notification_low_s: {type: int, default: 5, doc: "Seconds a low urgency popup stays at least", label: "Low popup", group: notifications, min: 1, max: 120, apply: live, scope: user}
    notification_normal_s: {type: int, default: 8, doc: "Seconds a normal popup stays at least; critical ones stay until dismissed", label: "Normal popup", group: notifications, min: 1, max: 120, apply: live, scope: user}
    notification_max_s: {type: int, default: 30, doc: "Seconds a popup stays at most, whatever its sender asks", label: "Popup at most", group: notifications, min: 1, max: 600, apply: live, scope: user}
    notification_history_max: {type: int, default: 30, doc: "Notifications kept in the history", label: "History", group: notifications, min: 1, max: 500, apply: live, scope: user}
    fx_glow: {type: float, default: 0.22, doc: "Accent glow around text and edges", label: "Glow", group: effects, min: 0.0, max: 1.0, step: 0.01, apply: live, scope: user}
    fx_scanlines: {type: float, default: 0.06, doc: "Opacity of the scanline overlay", label: "Scanlines", group: effects, min: 0.0, max: 0.3, step: 0.01, apply: live, scope: user}
    fx_flicker: {type: float, default: 0.02, doc: "CRT brightness flicker", label: "Flicker", group: effects, min: 0.0, max: 0.1, step: 0.01, apply: live, scope: user}
    fx_matrix_rain: {type: float, default: 0.5, doc: "Glyph rain on the lock screen", label: "Matrix rain", group: effects, min: 0.0, max: 1.0, step: 0.05, apply: live, scope: user}
    fx_corner_brackets: {type: bool, default: true, doc: "Corner brackets on panels and cards", label: "Corner brackets", group: effects, apply: live, scope: user}
}

const CONFIG_DIR = ".config/quickshell"
const SKIP = [mod.nu AGENTS.md .qmllint.ini .gitignore dotfiles-settings.desktop theme.json]
const SKIP_PATTERN = '(__pycache__|\.log$|\.qsb$|\.test\.(nu|sh)$)'

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

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let files = ls --long ...(glob --no-dir config/**/*) | update name { path relative-to ($env.PWD | path join config) }
        | where {|f| ($f.name | path basename) not-in $SKIP and $f.name !~ $SKIP_PATTERN }
    [
        # in place: quickshell's file watcher follows the inode, so a replaced copy can go unseen and never reload
        ($files | each {|f| file-copy ("config" | path join $f.name) ($dir | path join $f.name) --in-place --mode (if ($f.mode | str substring 2..2) == "x" { "755" } else { "644" }) })
        (link-commands ...(glob 'config/scripts/*.{nu,sh}' | where $it !~ $SKIP_PATTERN))
        # not enabled: hyprland_autostart.lua starts it
        (unit-file services/quickshell.service)
        (unit-file services/quickshell-reminders-rearm.service --enable)
        (pomodoro-config $cfg)
        (clipboard-config $cfg)
        (bar-config $cfg)
        (notify-config $cfg)
        (theme-config $cfg)
        # the settings window outside hyprland (settings-only.qml), listed in Plasma's launcher only
        (file-render config/dotfiles-settings.desktop (xdg data applications dotfiles-settings.desktop) {HOME: $nu.home-dir})
    ]
}

export def apply [cfg: record] {
    [(pomodoro-config $cfg) (clipboard-config $cfg) (bar-config $cfg) (notify-config $cfg) (theme-config $cfg)]
}
