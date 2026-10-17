use module.nu *

# wine comes from gaming/runtime's wine-staging, which provides the wine binary and conflicts with plain wine
export const meta = {packages: {pacman: [curl jq libnotify unzip wmctrl zenity zip]}}

# upstream dropped its aur package and tags releases without assets, so a pinned checkout is the only install path
const URL = "https://github.com/murkl/d2launcher.git"
const COMMIT = "73d6d145f1b8fd228fe7ac1263c4f4230d37ebea" # 4.1.3

# the script resolves its own res/ next to the real file, so the symlink in PATH is safe
def install-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join d2launcher
}

# SCRIPT_HOME_DIR is fixed in the script, it cannot be moved into XDG state
def home-dir []: nothing -> path { $nu.home-dir | path join .d2launcher }

# the game, the proton build and the save backups are bulk downloads, so they live with the other vendor payloads
def vendor-dir []: nothing -> path { $nu.home-dir | path join sync vendor d2launcher }

export def link [cfg: record] {
    let dir = install-dir
    let script = $dir | path join d2launcher
    let vendor = vendor-dir
    [
        (fetch-git $URL $COMMIT $dir)
        (file-link $script ($nu.home-dir | path join .local bin d2launcher))
        # the script mkdir -p's bin and backup on every run, which fails on a dangling symlink, so seed them first
        ...([bin backup wineprefix] | each {|d|
            let path = $vendor | path join $d
            exec $"d2launcher-vendor-($d)" [mkdir -p $path] --creates $path
        })
        # bin holds the game and the proton build, backup holds the save archives
        (file-link ($vendor | path join bin) (home-dir | path join bin))
        (file-link ($vendor | path join backup) (home-dir | path join backup))
        (file-text (home-dir | path join d2launcher.conf) (config))
        # the script writes this itself when absent, and forces a migration prompt over a plain d2launcher.desktop
        (file-text ($nu.home-dir | path join .local share applications d2launcher.local.desktop) (desktop $dir))
    ]
}

# every key the script would otherwise append on first run, so it never rewrites the file
def config []: nothing -> string {
    [
        'd2_exe="Diablo II.exe"'
        'd2_args="-3dfx"'
        'gui_width="450"'
        'gui_height="420"'
        # the pinned checkout is the version, a self update would silently overwrite it
        'update_check="false"'
        'mxl_update_check="true"'
        'mxl_update_channel="public"'
        'd2_stats_tray="true"'
        'gui_font="JetBrainsMono Nerd Font"'
        # sourced after the script's own default, so this wins; the Settings dialog rewrites the whole file and drifts
        $'wineprefix="(vendor-dir | path join wineprefix)"'
    ] | str join "\n" | $"($in)\n"
}

def desktop [dir: path]: nothing -> string {
    # StartupWMClass is zenity: the launcher is a zenity dialog, not a window of its own
    [
        "[Desktop Entry]"
        "Name=Diablo II"
        $"Icon=($dir | path join res icon.svg)"
        $"Exec=\"($dir | path join d2launcher)\""
        "Type=Application"
        "Terminal=false"
        "StartupWMClass=zenity"
    ] | str join "\n" | $"($in)\n"
}
