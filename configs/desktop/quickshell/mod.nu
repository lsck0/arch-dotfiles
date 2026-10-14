use module.nu *

export const meta = {
    deps: [desktop/hyprland]
    packages: {pacman: [cava inotify-tools libqalculate qrencode qt6-shadertools quickshell zenity]}
}

const CONFIG_DIR = ".config/quickshell"
const SKIP = [mod.nu AGENTS.md theme.json quickshell.service .qmllint.ini .gitignore]
const SKIP_PATTERN = '(__pycache__|\.log$|\.qsb$)'

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    let files = ls --long ...(glob --no-dir **/*) | update name { path relative-to $env.PWD }
        | where {|f| ($f.name | path basename) not-in $SKIP and $f.name !~ $SKIP_PATTERN }
    [
        ($files | each {|f| file-copy $f.name ($dir | path join $f.name) --mode (if ($f.mode | str substring 2..2) == "x" { "755" } else { "644" }) })
        # live-watched and saved by hand or by toggle-font, which edits the repo copy
        (file-link theme.json ($dir | path join theme.json))
        (link-commands ...(glob 'scripts/*.{nu,sh}'))
        # not enabled, hyprland_autostart.lua starts it
        (unit-file quickshell.service)
    ]
}
