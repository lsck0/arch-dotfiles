use module.nu *
use ../d2launcher/mod.nu [lod-detect wine-bin]

# Project Diablo 2 single player, plugy's big stash and stat/skill unassign included: its install and the saves stay in
# ~/sync, the lord of destruction base comes from the lutris prefix, linked together into a dir of its own.
export const meta = {deps: [gaming/d2launcher]}

const PD2_MARKER = "ProjectDiablo.dll"
const SAVE_KEY = 'HKCU\Software\Blizzard Entertainment\Diablo II'
const GAMES_DIR = "sync/games/d2"
const SIZE = {w: 1068, h: 600}

export const options = {
    game_dir: {
        type: string?
        default: null
        doc: "The ProjectD2 dir; detected under ~/sync/games/d2"
        label: "Project Diablo 2 install"
    }
    save_dir: {
        type: string?
        default: null
        doc: "The single player saves (.d2s, plugy's .d2x and .sss); detected as Save beside the install"
        label: "Save dir"
    }
}

export def detect [cfg: record]: nothing -> record {
    let games = $nu.home-dir | path join $GAMES_DIR
    let game = glob ($games | path join * $PD2_MARKER) | get --optional 0 | if $in == null { null } else { path dirname }
    let save = if $game == null { null } else { $game | path dirname | path join Save }
    {game_dir: $game, save_dir: (if $save != null and (glob ($save | path join *.d2s) | is-not-empty) { $save })}
}

def root []: nothing -> path {
    $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join pd2
}

def prefix-dir []: nothing -> path { root | path join prefix }

def lod-dir []: nothing -> path { root | path join "Diablo II" }

def wine-env []: nothing -> list<string> {
    [env $"WINEPREFIX=(prefix-dir)" WINEDEBUG=-all DISPLAY= WAYLAND_DISPLAY=]
}

# A windows path in the prefix's Z: drive, with the trailing separator diablo ii wants.
def z-path [dir: path]: nothing -> string {
    $"Z:($dir | str replace --all '/' '\')\\"
}

export def link [cfg: record] {
    let base = lod-detect
    if $cfg.game_dir == null or $base == null or not (wine-bin | path exists) { return [] }
    let wine = wine-bin | path dirname
    let reg = prefix-dir | path join user.reg
    [
        ...(ls $base | get name | each {|f| file-link $f (lod-dir | path join ($f | path basename)) })
        (file-link $cfg.game_dir (lod-dir | path join ProjectD2))
        (exec pd2-prefix [...(wine-env) ($wine | path join wineboot) --init] --creates $reg)
        (if $cfg.save_dir != null and not (save-path-set $cfg.save_dir) { step save-path $cfg.save_dir } else { [] })
        (file-render pd2.sh (root | path join pd2.sh) {
            game: (lod-dir | path join ProjectD2), prefix: (prefix-dir), wine: $wine, width: $SIZE.w, height: $SIZE.h
        } --mode "755")
        (file-text ($nu.home-dir | path join .local share applications pd2.desktop) (desktop))
    ]
}

def save-path-set [save: path]: nothing -> bool {
    let reg = prefix-dir | path join user.reg
    if not ($reg | path exists) { return false }
    let want = z-path $save | str replace --all '\' '\\'
    open --raw $reg | str contains $'"Save Path"="($want)"'
}

export def save-path [save: string]: nothing -> nothing {
    with-env {WINEPREFIX: (prefix-dir), WINEDEBUG: "-all", DISPLAY: "", WAYLAND_DISPLAY: ""} {
        ^(wine-bin) reg add $SAVE_KEY /v "Save Path" /t REG_SZ /d (z-path $save) /f | ignore
        ^(wine-bin | path dirname | path join wineserver) -w
    }
}

def desktop []: nothing -> string {
    [
        "[Desktop Entry]"
        "Name=Project Diablo II"
        "Comment=Diablo II single player with Project Diablo 2 and PlugY"
        $"Exec=(root | path join pd2.sh)"
        "Icon=applications-games"
        "Type=Application"
        "Terminal=false"
        "Categories=Game;"
    ] | str join "\n" | $"($in)\n"
}
