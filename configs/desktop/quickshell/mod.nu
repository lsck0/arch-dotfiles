use module.nu *

export const meta = {
    deps: [desktop/hyprland]
    packages: {pacman: [cava inotify-tools libqalculate qrencode qt6-shadertools quickshell zenity]}
}

export const options = {
    pomodoro_focus_min: {type: int, default: 25, doc: "Minutes of one focus block", label: "Focus", group: pomodoro, min: 1, max: 180, apply: live}
    pomodoro_break_min: {type: int, default: 5, doc: "Minutes of the short break after a focus block", label: "Break", group: pomodoro, min: 1, max: 60, apply: live}
    pomodoro_long_break_min: {type: int, default: 15, doc: "Minutes of the long break after the last focus block of a round", label: "Long break", group: pomodoro, min: 1, max: 120, apply: live}
    pomodoro_cycles: {type: int, default: 4, doc: "Focus blocks before a long break", label: "Cycles", group: pomodoro, min: 1, max: 12, apply: live}
}

const CONFIG_DIR = ".config/quickshell"
const SKIP = [mod.nu AGENTS.md theme.json quickshell.service .qmllint.ini .gitignore]
const SKIP_PATTERN = '(__pycache__|\.log$|\.qsb$|\.test\.(nu|sh)$)'

def pomodoro-config [cfg: record]: nothing -> record {
    let config = {focus: $cfg.pomodoro_focus_min, break: $cfg.pomodoro_break_min, long: $cfg.pomodoro_long_break_min, cycles: $cfg.pomodoro_cycles}
    file-text ($nu.home-dir | path join $CONFIG_DIR pomodoro.json) $"($config | to json --raw)\n" --generated
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let files = ls --long ...(glob --no-dir **/*) | update name { path relative-to $env.PWD }
        | where {|f| ($f.name | path basename) not-in $SKIP and $f.name !~ $SKIP_PATTERN }
    [
        ($files | each {|f| file-copy $f.name ($dir | path join $f.name) --mode (if ($f.mode | str substring 2..2) == "x" { "755" } else { "644" }) })
        # a link: quickshell watches it live and toggle-font edits the repo copy
        (file-link theme.json ($dir | path join theme.json))
        (link-commands ...(glob 'scripts/*.{nu,sh}'))
        # not enabled: hyprland_autostart.lua starts it
        (unit-file quickshell.service)
        (pomodoro-config $cfg)
    ]
}

export def apply [cfg: record] {
    pomodoro-config $cfg
}
