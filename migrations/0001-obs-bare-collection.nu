# the repo collection Fullscreen (full desktop, all audio) is Bare now, its one scene Desktop: the live copy is renamed
# in place, so obs keeps its portal token and lists no orphan Fullscreen beside the Bare that creating/obs installs

def scenes-dir []: nothing -> path {
    $nu.home-dir | path join .config obs-studio basic scenes
}

def rename [from: string, to: string, scene_from: string, scene_to: string]: nothing -> nothing {
    let src = scenes-dir | path join $"($from).json"
    let dest = scenes-dir | path join $"($to).json"
    if not ($src | path exists) { return }
    let user_ini = $nu.home-dir | path join .config obs-studio user.ini
    let selection = $"SceneCollectionFile=($from).json"
    let loaded = ($user_ini | path exists) and (open --raw $user_ini | lines | any { $in == $selection })
    # obs saves its loaded collection on exit, it would bring the old one back
    if $loaded and (ps | where name == obs | is-not-empty) {
        error make {msg: $"obs has the ($from) collection loaded, close it so it can become ($to)"}
    }
    # an apply before this migration installed the new one already; the old is then only an orphan
    if not ($dest | path exists) {
        let scene = {|n| if $n == $scene_from { $scene_to } else { $n } }
        open $src
        | update name $to
        | update scene_order { each { update name {|s| do $scene $s.name } } }
        | update current_scene {|c| do $scene $c.current_scene }
        | update current_program_scene {|c| do $scene $c.current_program_scene }
        | update sources { each {|s| if $s.id == "scene" { $s | update name (do $scene $s.name) } else { $s } } }
        | to json --indent 4 | save $dest
    }
    rm --force $src ($src | path parse | update extension "json.bak" | path join)
    if $loaded {
        open --raw $user_ini | lines | each {|l|
            match $l {
                $s if $s == $selection => $"SceneCollectionFile=($to).json"
                $s if $s == $"SceneCollection=($from)" => $"SceneCollection=($to)"
                _ => $l
            }
        } | str join "\n" | $"($in)\n" | save --force $user_ini
    }
}

export def up []: nothing -> nothing {
    rename Fullscreen Bare Fullscreen Desktop
}

export def down []: nothing -> nothing {
    rename Bare Fullscreen Desktop Fullscreen
}
