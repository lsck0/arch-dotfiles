use module.nu *
use ini.nu [ini-apply]

# no wine: gaming/runtime's wine-staging conflicts with it
export const meta = {packages: {pacman: [curl gamescope jq libnotify unzip wmctrl zenity zip]}}

# no aur package and releases without assets
const URL = "https://github.com/murkl/d2launcher.git"
const COMMIT = "73d6d145f1b8fd228fe7ac1263c4f4230d37ebea" # 4.1.3

def install-dir []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join d2launcher
}

# SCRIPT_HOME_DIR is hardcoded in the script
def home-dir []: nothing -> path { $nu.home-dir | path join .d2launcher }

def vendor-dir []: nothing -> path { $nu.home-dir | path join sync vendor d2launcher }

const VENDOR_LINKED = [bin patches backup]
const BASE_MARKER = "d2exp.mpq"
const BASE_IN_PREFIX = "drive_c/Program Files (x86)/Diablo II"
const PATCH_VERSION = "d2launcher-patch.version"
const D2_EXE = "Diablo II.exe"
const D2_ARGS = "-3dfx"
const MXL_MANIFEST = "https://launcher.median-xl.com/mxl/release/public/manifest"
# the game runs in gamescope (gamescope.sh): the window scales freely, so the old fixed-size wine virtual desktop goes
const OLD_DESKTOP_NAME = "Diablo II"
const RESOLUTION_FALLBACK = {desktop: "3840x2160", laptop: "1920x1080"}

export const options = {
    base_dir: {
        type: string?
        default: null
        doc: "A Diablo II: Lord of Destruction install the game dir is seeded from; detected in the lutris prefixes"
        label: "Diablo II install"
    }
    resolution: {
        type: string?
        default: null
        doc: "The monitor the render size derives from, WxH; detected from the focused monitor"
        label: "Resolution"
        scope: machine
    }
    render_size: {
        type: string?
        default: null
        doc: "The 4:3 size the game renders at inside gamescope, WxH; the monitor's full height by default"
        label: "Render size"
        scope: machine
    }
}

export def detect [cfg: record]: nothing -> record {
    let games = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join lutris games
    let prefixes = glob ($games | path join *.yml)
        | each {|f| try { open $f | get --optional game.prefix } catch { null } }
    let base = $prefixes | compact | each { path expand | path join $BASE_IN_PREFIX }
        | where { path join $BASE_MARKER | path exists } | get --optional 0
    let monitor = try {
        ^hyprctl -j monitors | from json | where name !~ "^HEADLESS-" | sort-by focused --reverse | first
    } catch { null }
    {base_dir: $base, resolution: (if $monitor == null { null } else { $"($monitor.width)x($monitor.height)" })}
}

def game-dir []: nothing -> path { home-dir | path join bin diablo2 }

export def link [cfg: record] {
    let dir = install-dir
    let script = $dir | path join d2launcher
    let vendor = vendor-dir
    let game = game-dir
    let base = $cfg.base_dir | default ""
    let seedable = $base != "" and ($base | path join $BASE_MARKER | path exists)
    let seeded = $game | path join $BASE_MARKER | path exists
    let game_empty = ($game | path type) == dir and (ls $game | is-empty)
    [
        (fetch-git $URL $COMMIT $dir)
        (file-link $script ($nu.home-dir | path join .local bin d2launcher))
        # the script mkdir -p's bin and backup on every run, which fails on a dangling symlink, so seed them first
        ...($VENDOR_LINKED ++ [wineprefix] | each {|d|
            let path = $vendor | path join $d
            exec $"d2launcher-vendor-($d)" [mkdir -p $path] --creates $path
        })
        ...($VENDOR_LINKED | each {|d| file-link ($vendor | path join $d) (home-dir | path join $d) })
        (if ($seedable and not $seeded) or $game_empty { step game-seed $base } else { [] })
        # -3dfx needs the glide3x.dll only a median xl patch brings
        (if ($seedable or $seeded) and not ($game | path join $PATCH_VERSION | path exists) {
            step mxl-install
        } else { [] })
        (file-text (home-dir | path join d2launcher.conf) (config))
        (file-render gamescope.sh (home-dir | path join gamescope.sh) (gamescope-values $cfg))
        (d2gl-window-decl $cfg)
        (wine-desktop-decl)
        # the script forces a migration prompt over a plain d2launcher.desktop
        (file-text ($nu.home-dir | path join .local share applications d2launcher.local.desktop) (desktop $dir))
    ]
}

# every key, or the script appends the missing ones
def config []: nothing -> string {
    [
        $'d2_exe="($D2_EXE)"'
        $'d2_args="($D2_ARGS)"'
        'gui_width="450"'
        'gui_height="420"'
        'update_check="false"'
        'mxl_update_check="true"'
        'mxl_update_channel="public"'
        'd2_stats_tray="true"'
        'gui_font="JetBrainsMono Nerd Font"'
        $'wineprefix="(prefix-dir)"'
        $"custom_command=\"bash '(home-dir | path join gamescope.sh)'\""
    ] | str join "\n" | $"($in)\n"
}

def resolution [cfg: record]: nothing -> record {
    let text = $cfg.resolution | default ($RESOLUTION_FALLBACK | get --optional ($env.FORM_FACTOR? | default desktop)
        | default $RESOLUTION_FALLBACK.desktop)
    $text | parse "{w}x{h}" | get 0 | {w: ($in.w | into int), h: ($in.h | into int)}
}

# a multiple of 12 keeps both sides of 4:3 whole and even
def render-size [cfg: record]: nothing -> record {
    if $cfg.render_size != null {
        return ($cfg.render_size | parse "{w}x{h}" | get 0 | {w: ($in.w | into int), h: ($in.h | into int)})
    }
    let h = (resolution $cfg).h | $in - ($in mod 12)
    {w: ($h // 3 * 4), h: $h}
}

def gamescope-values [cfg: record]: nothing -> record {
    let size = render-size $cfg
    {
        game: (game-dir), prefix: (prefix-dir), width: $size.w, height: $size.h, args: $D2_ARGS
        wine: (wine-bin | path dirname), exe: (game-dir | path join $D2_EXE)
    }
}

# d2gl's window fills gamescope's nested screen
def d2gl-window-keys [cfg: record]: nothing -> record {
    let size = render-size $cfg
    {Screen: {window_width: ($size.w | into string), window_height: ($size.h | into string), centered_window: "true"}}
}

def d2gl-window-decl [cfg: record]: nothing -> list<record> {
    let ini = game-dir | path join d2gl.ini
    if not (game-dir | path join $PATCH_VERSION | path exists) { return [] }
    let want = d2gl-window-keys $cfg
    let lines = if ($ini | path exists) { open --raw $ini | lines | each { str trim } } else { [] }
    let start = $lines | enumerate | where item == "[Screen]" | get --optional 0.index
    let have = if $start == null { {} } else {
        $lines | skip ($start + 1) | take while { not ($in | str starts-with "[") } | where ($it =~ '^[^;].*=')
            | parse "{key}={value}" | if ($in | is-empty) { {} } else { transpose -r -d }
    }
    if ($want.Screen | columns | all {|k| ($have | get --optional $k) == ($want.Screen | get $k) }) { return [] }
    [(step d2gl-window ($want.Screen.window_width) ($want.Screen.window_height))]
}

export def d2gl-window [width: string, height: string]: nothing -> nothing {
    let ini = game-dir | path join d2gl.ini
    let keys = {Screen: {window_width: $width, window_height: $height, centered_window: true}}
    let text = if ($ini | path exists) { open --raw $ini } else { "" }
    $text | ini-apply $keys false | save -f $ini
}

def wine-bin []: nothing -> path { home-dir | path join bin wine bin wine }

def prefix-dir []: nothing -> path { vendor-dir | path join wineprefix }

def wine-desktop-set []: nothing -> bool {
    let reg = prefix-dir | path join user.reg
    if not ($reg | path exists) { return false }
    open --raw $reg | split row "\n[" | where ($it | str starts-with 'Software\\Wine\\Explorer]')
        | any { lines | any { str starts-with '"Desktop"=' } }
}

def wine-desktop-decl []: nothing -> list<record> {
    if not ((wine-bin | path exists) and (wine-desktop-set)) { return [] }
    [(step wine-desktop-remove)]
}

# the launcher's own wine: the system's would upgrade the prefix
export def wine-desktop-remove []: nothing -> nothing {
    let env_vars = {WINEPREFIX: (prefix-dir), DISPLAY: "", WAYLAND_DISPLAY: "", WINEDEBUG: "-all"}
    with-env $env_vars {
        # user.reg lags a running wineserver, so a value may already be gone
        try { ^(wine-bin) reg delete 'HKCU\Software\Wine\Explorer' /v Desktop /f }
        try { ^(wine-bin) reg delete 'HKCU\Software\Wine\Explorer\Desktops' /v $OLD_DESKTOP_NAME /f }
        try { ^(wine-bin) reg delete 'HKCU\Software\Wine\X11 Driver' /v Decorated /f }
    }
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

# the launcher asks for the game dir only while bin/diablo2 is missing, so an empty one cannot start
export def game-seed [base: string]: nothing -> nothing {
    let game = game-dir
    if $base != "" and ($base | path join $BASE_MARKER | path exists) {
        mkdir $game
        let files = ls $base | where type == file | get name
        ^cp --reflink=auto --no-clobber ...$files $game
    } else if ($game | path type) == dir and (ls $game | is-empty) {
        ^rmdir $game
    }
}

export def mxl-install []: nothing -> nothing {
    let game = game-dir
    let manifest = http get $MXL_MANIFEST
    let name = $"d2launcher-mxl-($manifest.tag)"
    let zip = home-dir | path join patches $"($name).zip"
    if not ($zip | path exists) {
        let tmp = mktemp --directory --tmpdir d2launcher-mxl.XXXXXX
        for file in ($manifest.files | get name) {
            (^curl -fLs --get $manifest.location --data-urlencode $"type=($manifest.channel)"
                --data-urlencode $"tag=($manifest.tag)" --data-urlencode $"file=($file)" -o ($tmp | path join $file))
        }
        do { cd $tmp; ^zip -q -r -0 $"($zip).part" . }
        mv $"($zip).part" $zip
        rm -rf $tmp
    }
    ^unzip -q -o (install-dir | path join res d2-patch.zip) -d $game
    ^unzip -q -o $zip -d $game
    $name | save -f ($game | path join $PATCH_VERSION)
}
