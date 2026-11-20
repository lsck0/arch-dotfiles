use module.nu *

# points the overlay at Steam's PoE log and Proton config; its own config exists only after a first start
export const meta = {volatile: true, packages: {pacman: [awakened-poe-trade-bin]}}

export def link [cfg: record] {
    let steam = $nu.home-dir | path join .local share Steam steamapps
    let config = xdg config awakened-poe-trade apt-data config.json
    if not ($config | path exists) { return [] }
    let edits = [
        [clientLog ($steam | path join common "Path of Exile" logs Client.txt)]
        [gameConfig ($steam | path join compatdata 238960 pfx drive_c users steamuser Documents "My Games" "Path of Exile" production_Config.ini)]
    ] | where { $in.1 | path exists } | each { json-set [$in.0] $in.1 }
    if ($edits | is-empty) { [] } else { [(json-merge $config $edits)] }
}
