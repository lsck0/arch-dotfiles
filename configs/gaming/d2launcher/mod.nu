use module.nu *
use ini.nu [ini-apply ini-rows]

# no wine: desktop/applications' wine-staging conflicts with it
export const meta = {packages: {pacman: [curl gamescope jq libnotify unzip wmctrl zenity zip]}}

const URL = "https://github.com/murkl/d2launcher.git"
const COMMIT = "73d6d145f1b8fd228fe7ac1263c4f4230d37ebea" # 4.1.3
const HERE = path self .

def install-dir []: nothing -> path { xdg data d2launcher }

# SCRIPT_HOME_DIR is hardcoded in the script.
def home-dir []: nothing -> path { $nu.home-dir | path join .d2launcher }

def synced-vendor []: nothing -> path { $nu.home-dir | path join sync vendor d2launcher }

# The fallback vendor dir is dot's; a synced one is read-only to it (nothing lands in ~/sync). The owner's machines get
# the vendor dir from syncthing; on a fresh one it can arrive after the first apply, and a fallback built meanwhile
# (wine, a copied game, Median XL) would be left behind once it does.
def vendor-own []: nothing -> bool { not (synced-vendor | path exists) and not (profile-has secrets) }

def vendor-dir []: nothing -> path { if (vendor-own) { xdg data d2launcher-vendor } else { synced-vendor } }

# d2launcher's own wine (its wine_native_url at COMMIT); valve's tree reports itself as wine-5.12-15359-g492470267af
const WINE_URL = "https://github.com/Kron4ek/Wine-Builds/releases/download/7.0-5-proton/wine-7.0-5-proton-amd64.tar.xz"
const WINE_SHA256 = "fbfddbab42be0f3c6d9f6f0b9b899a8503e50358bde659621a83fbe7ca83bbca"
const WINE_TOP = "wine-7.0-5-proton-amd64"

# Fetched into the fallback vendor dir only: a synced vendor dir brings its own copy.
def wine-fetch-decl []: nothing -> list<record> {
    if not (vendor-own) { return [] }
    fetch-file $WINE_URL $WINE_SHA256 (vendor-dir | path join bin wine) --extract $WINE_TOP
}

def wine-ready []: nothing -> bool { (wine-bin | path exists) or (wine-fetch-decl | is-not-empty) }

const VENDOR_LINKED = [bin patches backup]
const BASE_MARKER = "d2exp.mpq"
const BASE_IN_PREFIX = "drive_c/Program Files (x86)/Diablo II"
const PATCH_VERSION = "d2launcher-patch.version"
const D2_EXE = "Diablo II.exe"
const D2_ARGS = "-3dfx"
const MXL_MANIFEST = "https://launcher.median-xl.com/mxl/release/public/manifest"
const MXL_FILES = "https://get.median-xl.com/"
const OLD_DESKTOP_NAME = "Diablo II"
const RESOLUTION_FALLBACK = {desktop: "3840x2160", laptop: "1920x1080"}
const SAVE_KEY = 'HKCU\Software\Blizzard Entertainment\Diablo II'
# plain lord of destruction keeps its characters here once the dir exists; dot never creates dirs in ~/sync
const VANILLA_SAVE = "sync/games/d2/Save-LoD"

export const options = {
    base_dir: {
        type: string?
        default: null
        doc: "A Diablo II: Lord of Destruction install the game dir is seeded from; detected in the lutris prefixes"
        label: "Diablo II install"
        scope: user
    }
    resolution: {
        type: string?
        default: null
        doc: "The monitor the render size derives from, WxH; detected from the focused monitor"
        label: "Resolution"
    }
    render_size: {
        type: string?
        default: null
        doc: "The 4:3 size the game renders at inside gamescope, WxH; the monitor's full height by default"
        label: "Render size"
    }
}

# lutris prefixes first, then ~/sync/games/d2 (a fresh install has no lutris entry)
def lod-detect []: nothing -> any {
    let games = xdg data lutris games
    let lutris = glob ($games | path join *.yml)
        | each {|f| try { open $f | get --optional game.prefix } catch { null } } | compact
    let synced = glob ($nu.home-dir | path join sync games d2 * drive_c) | path dirname
    $lutris ++ $synced | each { path expand | path join $BASE_IN_PREFIX }
        | where { path join $BASE_MARKER | path exists } | get --optional 0
}

# The launcher's own wine (5.12): 1.13c game.exe overflows its stack under the system's wine-staging.
export def wine-bin []: nothing -> path { home-dir | path join bin wine bin wine }

export def detect [cfg: record]: nothing -> record {
    let base = lod-detect
    let monitor = monitors-live | sort-by focused --reverse | get --optional 0
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
    let own = vendor-own
    if not (synced-vendor | path exists) and (profile-has secrets) {
        log-note "d2launcher: waiting for syncthing to bring ~/sync/vendor/d2launcher; apply again once it is there"
    } else if not $own and not ($game | path join $PATCH_VERSION | path exists) {
        log-note $"d2launcher: ($game) is not set up in the synced vendor dir; set it up on the machine that owns it"
    }
    [
        (fetch-git $URL $COMMIT $dir)
        (file-link $script ($nu.home-dir | path join .local bin d2launcher))
        # the script mkdir -p's bin and backup on every run, which fails on a dangling symlink, so seed them first
        (if $own {
            $VENDOR_LINKED ++ [wineprefix] | each {|d|
                let path = $vendor | path join $d
                exec $"d2launcher-vendor-($d)" [mkdir -p $path] --creates $path
            }
        })
        ...($VENDOR_LINKED | each {|d| file-link ($vendor | path join $d) (home-dir | path join $d) })
        ...(wine-fetch-decl)
        # chmod only: syncthing ignores permissions, so this changes no synced content
        (step wine-bin-fixup --done=(wine-bin-unexecutable | is-empty))
        (if $own { step game-seed $base --done=(not (($seedable and not $seeded) or $game_empty)) })
        (if $own and ($seedable or $seeded) { step mxl-install --network --creates ($game | path join $PATCH_VERSION) })
        (file-text (home-dir | path join d2launcher.conf) (config))
        (game-script (home-dir | path join gamescope.sh) (gamescope-values $cfg))
        (if $own { d2gl-window-decl $cfg })
        (wine-desktop-decl)
        # the script forces a migration prompt over a plain d2launcher.desktop; StartupWMClass is zenity: the launcher
        # is a zenity dialog, not a window of its own
        (desktop-entry d2launcher.local {
            Name: "Median XL", Icon: ($dir | path join res icon.svg), Exec: $'"($script)"', Type: Application
            Terminal: false, StartupWMClass: zenity
        })
        ...(vanilla-decls $cfg)
    ]
}

# The environment every wine call of this module and pd2 runs under: no window system, no debug output.
def wine-env [prefix: path]: nothing -> record {
    {WINEPREFIX: $prefix, WINEDEBUG: "-all", DISPLAY: "", WAYLAND_DISPLAY: ""}
}

# A game's own tree on this wine (plain LoD here, each pd2 season): its prefix, its lord of destruction dir.
export def wine-tree [name: string]: nothing -> record {
    let root = xdg data $name
    {root: $root, prefix: ($root | path join prefix), lod: ($root | path join "Diablo II")}
}

# The lord of destruction base linked into a tree, so the game's logs land there, and the tree's prefix.
export def wine-tree-decls [tree: record, base: path]: nothing -> list<record> {
    let env_vars = wine-env $tree.prefix | items {|k, v| $"($k)=($v)" }
    [
        ...(ls $base | get name | each {|f| file-link $f ($tree.lod | path join ($f | path basename)) })
        (exec $"($tree.root | path basename)-prefix" [env ...$env_vars (wine-bin | path dirname | path join wineboot) --init]
            --creates ($tree.prefix | path join user.reg) --requires (wine-bin))
    ]
}

# A gamescope launcher from gamescope.sh: game, prefix, exe, width, height and name given, args and dll_overrides
# optional.
def game-script [dest: path, values: record]: nothing -> record {
    let all = {wine: (wine-bin | path dirname), args: "", dll_overrides: ""} | merge $values
    file-render ($HERE | path join gamescope.sh) $dest $all --mode "755"
}

def desktop-entry [id: string, keys: record]: nothing -> record {
    let lines = $keys | items {|k, v| $"($k)=($v)" } | prepend "[Desktop Entry]"
    file-text (xdg data applications $"($id).desktop") ($lines | to text)
}

# A game's launcher script with its desktop entry <id>.desktop, titled title.
export def game-launcher [script: path, id: string, title: string, comment: string, values: record]: nothing -> list<record> {
    [
        (game-script $script $values)
        (desktop-entry $id {
            Name: $title, Comment: $comment, Exec: $script, Icon: applications-games, Type: Application, Terminal: false
            Categories: "Game;"
        })
    ]
}

def vanilla-decls [cfg: record]: nothing -> list<record> {
    let base = $cfg.base_dir
    if $base == null or not (wine-ready) { return [] }
    let tree = wine-tree diablo2
    let save = $nu.home-dir | path join $VANILLA_SAVE
    let title = "Diablo II: Lord of Destruction"
    [
        ...(wine-tree-decls $tree $base)
        (if ($save | path exists) { step save-path $tree.prefix $save --done=(save-path-set $tree.prefix $save) --requires (wine-bin) })
        # windowed: its direct3d fullscreen mode fails under wine at most sizes
        ...(game-launcher ($tree.root | path join diablo2.sh) diablo2 $title "Plain Diablo II with Lord of Destruction 1.14d" {
            game: $tree.lod, prefix: $tree.prefix, exe: Game.exe, args: "-w", width: 800, height: 600, name: $title
        })
    ]
}

# A windows path in the prefix's Z: drive, with the trailing separator diablo ii wants.
export def z-path [dir: path]: nothing -> string {
    $"Z:($dir | str replace --all '/' '\')\\"
}

# Shared with pd2's prefixes, which run on this wine.
export def save-path-set [prefix: path, save: path]: nothing -> bool {
    let reg = $prefix | path join user.reg
    if not ($reg | path exists) { return false }
    let want = z-path $save | str replace --all '\' '\\'
    open --raw $reg | str contains $'"Save Path"="($want)"'
}

export def save-path [prefix: string, save: string]: nothing -> nothing {
    with-env (wine-env $prefix) {
        ^(wine-bin) reg add $SAVE_KEY /v "Save Path" /t REG_SZ /d (z-path $save) /f | ignore
        ^(wine-bin | path dirname | path join wineserver) -w
    }
}

# Every key, or the script appends the missing ones.
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
    ] | to text
}

def parse-wxh [text: string]: nothing -> record {
    $text | parse "{w}x{h}" | get 0 | {w: ($in.w | into int), h: ($in.h | into int)}
}

def resolution [cfg: record]: nothing -> record {
    let text = $cfg.resolution | default ($RESOLUTION_FALLBACK | get --optional ($env.FORM_FACTOR? | default desktop)
        | default $RESOLUTION_FALLBACK.desktop)
    parse-wxh $text
}

# A multiple of 12 keeps both sides of 4:3 whole and even.
def render-size [cfg: record]: nothing -> record {
    if $cfg.render_size != null {
        return (parse-wxh $cfg.render_size)
    }
    let h = (resolution $cfg).h | $in - ($in mod 12)
    {w: ($h // 3 * 4), h: $h}
}

def gamescope-values [cfg: record]: nothing -> record {
    let size = render-size $cfg
    {
        game: (game-dir), prefix: (prefix-dir), width: $size.w, height: $size.h, args: $D2_ARGS
        exe: (game-dir | path join $D2_EXE), name: "Diablo II"
    }
}

# gamescope paces the frames; d2gl's own vsync on top adds frames of cursor lag
def d2gl-screen-keys [width: string, height: string]: nothing -> record {
    {Screen: {window_width: $width, window_height: $height, centered_window: "true", vsync: "false"}}
}

def d2gl-ini-text []: nothing -> string {
    let ini = game-dir | path join d2gl.ini
    if ($ini | path exists) { open --raw $ini } else { "" }
}

def d2gl-window-decl [cfg: record]: nothing -> list<record> {
    if not (game-dir | path join $PATCH_VERSION | path exists) { return [] }
    let size = render-size $cfg | update cells { into string }
    let want = (d2gl-screen-keys $size.w $size.h).Screen
    let have = ini-rows (d2gl-ini-text) | where section == Screen and key != null
        | reduce --fold {} {|r, acc| $acc | upsert ($r.key | str trim) ($r.value | str trim) }
    let set = $want | columns | all {|k| ($have | get --optional $k) == ($want | get $k) }
    [(step d2gl-window $size.w $size.h --done=$set)]
}

export def d2gl-window [width: string, height: string]: nothing -> nothing {
    d2gl-ini-text | ini-apply (d2gl-screen-keys $width $height) false | save --force (game-dir | path join d2gl.ini)
}

# ~/sync ignores permissions (core/syncthing, ignorePerms), so a resync silently drops wine's execute bit
def wine-bin-unexecutable []: nothing -> list<path> {
    let dir = wine-bin | path dirname
    if not ($dir | path exists) { return [] }
    ls --long $dir | where type == file and ($it.mode | str substring 2..2) != "x" | get name
}

export def wine-bin-fixup []: nothing -> nothing {
    ^chmod +x ...(wine-bin-unexecutable)
}

def prefix-dir []: nothing -> path { vendor-dir | path join wineprefix }

def wine-desktop-set []: nothing -> bool {
    let reg = prefix-dir | path join user.reg
    if not ($reg | path exists) { return false }
    open --raw $reg | split row "\n[" | where ($it | str starts-with 'Software\\Wine\\Explorer]')
        | any { lines | any { str starts-with '"Desktop"=' } }
}

def wine-desktop-decl []: nothing -> list<record> {
    if not (wine-bin | path exists) { return [] }
    [(step wine-desktop-remove --done=(not (wine-desktop-set)))]
}

# Uses the launcher's own wine: the system's would upgrade the prefix.
export def wine-desktop-remove []: nothing -> nothing {
    with-env (wine-env (prefix-dir)) {
        # user.reg lags a running wineserver, so a value may already be gone
        try { ^(wine-bin) reg delete 'HKCU\Software\Wine\Explorer' /v Desktop /f }
        try { ^(wine-bin) reg delete 'HKCU\Software\Wine\Explorer\Desktops' /v $OLD_DESKTOP_NAME /f }
        try { ^(wine-bin) reg delete 'HKCU\Software\Wine\X11 Driver' /v Decorated /f }
    }
}

# The launcher asks for the game dir only while bin/diablo2 is missing, so an empty one cannot start.
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
    # the manifest names the files and the host they come from, so neither may point anywhere else
    if not ($manifest.location | str starts-with $MXL_FILES) {
        error make {msg: $"mxl: manifest location ($manifest.location) is not on ($MXL_FILES)"}
    }
    let bad = $manifest.files.name | where {|f| ($f | path basename) != $f or $f in [. ..] }
    if ($bad | is-not-empty) {
        error make {msg: $"mxl: manifest file names leave the download dir: ($bad | str join ', ')"}
    }
    if $manifest.tag !~ '^[A-Za-z0-9._-]+$' {
        error make {msg: $"mxl: manifest tag '($manifest.tag)' is no plain name"}
    }
    let name = $"d2launcher-mxl-($manifest.tag)"
    let zip = home-dir | path join patches $"($name).zip"
    if not ($zip | path exists) {
        let tmp = mktemp --directory --tmpdir d2launcher-mxl.XXXXXX
        try {
            for file in $manifest.files {
                let out = $tmp | path join $file.name
                (^curl -fsSL --get $manifest.location --data-urlencode $"type=($manifest.channel)"
                    --data-urlencode $"tag=($manifest.tag)" --data-urlencode $"file=($file.name)" -o $out)
                # the manifest carries a sha1 per file: catches a truncated or swapped download, not a hostile server
                let sum = ^sha1sum $out | split row " " | first
                if $file.sha1? != null and $sum != $file.sha1 {
                    error make {msg: $"mxl: ($file.name) has sha1 ($sum), the manifest says ($file.sha1)"}
                }
            }
            do { cd $tmp; ^zip -q -r -0 $"($zip).part" . }
            mv $"($zip).part" $zip
        } catch {|e|
            rm -rf $tmp
            error make $e
        }
        rm -rf $tmp
    }
    ^unzip -q -o (install-dir | path join res d2-patch.zip) -d $game
    ^unzip -q -o $zip -d $game
    $name | save -f ($game | path join $PATCH_VERSION)
}
