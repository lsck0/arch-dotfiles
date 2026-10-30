use module.nu *
use ../d2launcher/mod.nu [lod-detect save-path-set wine-bin z-path]
# re-exported: the save-path step runs in this module
export use ../d2launcher/mod.nu [save-path]

# S14 from PD2's client host (no plugy), S3 synced with plugy; S3 saves can't move to S14.
export const meta = {deps: [gaming/d2launcher]}

const PD2_MARKER = "ProjectDiablo.dll"
const GAMES_DIR = "sync/games/d2"
const SIZE = {w: 1068, h: 600}
const S14_URL = "https://pd2-client-files.projectdiablo2.com"
const S14_SAVE = "Save-S14"
const HERE = path self | path dirname

export const options = {
    game_dir: {
        type: string?
        default: null
        doc: "The season 3 ProjectD2 dir; detected under ~/sync/games/d2"
        label: "Project Diablo 2 S3 install"
        scope: user
    }
    save_dir: {
        type: string?
        default: null
        doc: "Season 3's single player saves (.d2s, plugy's .d2x and .sss); detected as Save beside the install"
        label: "S3 save dir"
        scope: user
    }
    s14_save_dir: {
        type: string?
        default: null
        doc: "Season 14's single player saves and shared stash; detected as ~/sync/games/d2/Save-S14 when it exists"
        label: "S14 save dir"
        scope: user
    }
}

export def detect [cfg: record]: nothing -> record {
    let games = $nu.home-dir | path join $GAMES_DIR
    let game = glob ($games | path join * $PD2_MARKER) | get --optional 0 | if $in == null { null } else { path dirname }
    let save = if $game == null { null } else { $game | path dirname | path join Save }
    let s14 = $games | path join $S14_SAVE
    {
        game_dir: $game
        save_dir: (if $save != null and (glob ($save | path join *.d2s) | is-not-empty) { $save })
        s14_save_dir: (if ($s14 | path exists) { $s14 })
    }
}

# Each season's own tree: its prefix, its lord of destruction dir with ProjectD2 inside, its launcher.
def season [name: string]: nothing -> record {
    let root = xdg data $name
    {root: $root, prefix: ($root | path join prefix), lod: ($root | path join "Diablo II")}
}

def lod-links [base: path, lod: path]: nothing -> list<record> {
    ls $base | get name | each {|f| file-link $f ($lod | path join ($f | path basename)) }
}

def prefix-init [s: record, wine: path]: nothing -> record {
    exec $"($s.root | path basename)-prefix" [env $"WINEPREFIX=($s.prefix)" WINEDEBUG=-all DISPLAY= WAYLAND_DISPLAY= ($wine | path join wineboot) --init] --creates ($s.prefix | path join user.reg)
}

export def link [cfg: record] {
    let base = $cfg.deps?."gaming/d2launcher"?.base_dir? | default (lod-detect)
    if $base == null or not (wine-bin | path exists) { return [] }
    let wine = wine-bin | path dirname
    (s14 $cfg $base $wine) ++ (s3 $cfg $base $wine) | decls-flatten
}

def s14 [cfg: record, base: path, wine: path]: nothing -> list {
    let s = season pd2-s14
    let game = $s.lod | path join ProjectD2
    [
        (lod-links $base $s.lod)
        (open ($HERE | path join s14-client.nuon) | each {|f|
            fetch-file $"($S14_URL)/($f.name | url encode)" $f.sha256 ($game | path join $f.name)
        })
        (prefix-init $s $wine)
        # season 14 reads its save dir from its own settings, not the registry; the game fills in every other key
        (if $cfg.s14_save_dir == null { [] } else {
            json-merge ($game | path join ProjectDiablo.json) [(json-set [classic_game_settings other save_path] (z-path $cfg.s14_save_dir))]
        })
        (file-render pd2.sh ($s.root | path join pd2.sh) {
            game: $game, prefix: $s.prefix, wine: $wine, width: $SIZE.w, height: $SIZE.h, exe: "Game.exe"
        } --mode "755")
        (file-text (xdg data applications pd2.desktop) (desktop "Project Diablo II"
            "Diablo II single player, Project Diablo 2 season 14" ($s.root | path join pd2.sh)))
    ]
}

def s3 [cfg: record, base: path, wine: path]: nothing -> list {
    if $cfg.game_dir == null { return [] }
    let s = season pd2
    [
        (lod-links $base $s.lod)
        (file-link $cfg.game_dir ($s.lod | path join ProjectD2))
        (prefix-init $s $wine)
        (if $cfg.save_dir != null and not (save-path-set $s.prefix $cfg.save_dir) { step save-path $s.prefix $cfg.save_dir } else { [] })
        (file-render pd2.sh ($s.root | path join pd2.sh) {
            game: ($s.lod | path join ProjectD2), prefix: $s.prefix, wine: $wine, width: $SIZE.w, height: $SIZE.h, exe: "PlugY.exe"
        } --mode "755")
        (file-text (xdg data applications pd2-s3.desktop) (desktop "Project Diablo II S3"
            "Diablo II single player, Project Diablo 2 season 3 with PlugY" ($s.root | path join pd2.sh)))
    ]
}

def desktop [name: string, comment: string, exec: path]: nothing -> string {
    [
        "[Desktop Entry]"
        $"Name=($name)"
        $"Comment=($comment)"
        $"Exec=($exec)"
        "Icon=applications-games"
        "Type=Application"
        "Terminal=false"
        "Categories=Game;"
    ] | str join "\n" | $"($in)\n"
}
