use module.nu *
use ../d2launcher/mod.nu [game-launcher save-path-set wine-bin wine-tree wine-tree-decls z-path]
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

export def link [cfg: record] {
    let base = $cfg.deps?."gaming/d2launcher"?.base_dir?
    if $base == null or not (wine-bin | path exists) { return [] }
    [(s14 $cfg $base) (s3 $cfg $base)]
}

# project diablo 2's dll checks that its own dir sits inside a lord of destruction install, hence ProjectD2 in the tree
def season-launcher [s: record, exe: string, id: string, title: string, comment: string]: nothing -> list<record> {
    game-launcher ($s.root | path join pd2.sh) $id $title $comment {
        game: ($s.lod | path join ProjectD2), prefix: $s.prefix, exe: $exe, width: $SIZE.w, height: $SIZE.h
        name: "Project Diablo II", dll_overrides: "ddraw=n,b"
    }
}

def s14 [cfg: record, base: path]: nothing -> list {
    let s = wine-tree pd2-s14
    let game = $s.lod | path join ProjectD2
    [
        (wine-tree-decls $s $base)
        (open ($HERE | path join s14-client.nuon) | each {|f|
            fetch-file $"($S14_URL)/($f.name | url encode)" $f.sha256 ($game | path join $f.name)
        })
        # season 14 reads its save dir from its own settings, not the registry; the game fills in every other key
        (if $cfg.s14_save_dir != null {
            json-merge ($game | path join ProjectDiablo.json) [(json-set [classic_game_settings other save_path] (z-path $cfg.s14_save_dir))]
        })
        (season-launcher $s Game.exe pd2 "Project Diablo II" "Diablo II single player, Project Diablo 2 season 14")
    ]
}

def s3 [cfg: record, base: path]: nothing -> list {
    if $cfg.game_dir == null { return [] }
    let s = wine-tree pd2
    [
        (wine-tree-decls $s $base)
        (file-link $cfg.game_dir ($s.lod | path join ProjectD2))
        (if $cfg.save_dir != null { step save-path $s.prefix $cfg.save_dir --done=(save-path-set $s.prefix $cfg.save_dir) })
        (season-launcher $s PlugY.exe pd2-s3 "Project Diablo II S3" "Diablo II single player, Project Diablo 2 season 3 with PlugY")
    ]
}
