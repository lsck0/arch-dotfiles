use module.nu *

export const meta = {packages: {pacman: [rsync xivlauncher-bin]}, backup: {secrets: true}}

export const XLCORE = ".xlcore"

export const options = {
    mangohud: {
        type: bool
        default: true
        doc: "Start XIVLauncher with MANGOHUD=1, the overlay over the game"
        label: "MangoHud"
        scope: user
    }
}

def paths []: nothing -> record {
    let xl = $nu.home-dir | path join $XLCORE
    let saved = secret-path state ffxiv
    {
        xl: $xl, config: ($xl | path join ffxivConfig), launcher: ($xl | path join launcher.ini)
        seed: {config: (host-seed $saved ffxivConfig), launcher: (host-seed $saved launcher.ini)}
        saved: (host-file $saved)
    }
}

# Seeded once: the game rewrites these files in place.
export def link [cfg: record] {
    let p = paths
    let launcher = if $cfg.mangohud { desktop-exec XIVLauncher.desktop xivlauncher-core --env-vars {MANGOHUD: "1"} }
    let unlocked = secret-is-plaintext $p.seed.launcher
    if (which xivlauncher-core | is-empty) or not $unlocked { return $launcher }
    # read from the seed until the first apply copies it, so GamePath exists before the launcher's first start
    let ini = if ($p.launcher | path exists) { $p.launcher } else { $p.seed.launcher }
    let game = open --raw $ini | lines | parse "GamePath={path}" | get --optional 0.path
    [
        $launcher
        (step seed --creates ($p.config | path join FFXIV.cfg))
        (exec ffxiv-launcher [cp -n $p.seed.launcher $p.launcher] --creates $p.launcher)
        # the launcher's free-space check throws DriveNotFoundException while GamePath is missing (before an install)
        (if ($game | is-not-empty) { exec ffxiv-game-path [mkdir -p $game] --creates $game })
    ]
}

export def seed []: nothing -> nothing {
    let p = paths
    mkdir $p.config
    ^cp -rnT $p.seed.config $p.config
    secret-seed-mark $p.config
}

export def backup [cfg: record]: nothing -> nothing {
    let p = paths
    if not ($p.config | path join FFXIV.cfg | path exists) { error make {msg: $"no ($p.config)/FFXIV.cfg"} }
    secret-seed-guard $p.config $p.seed.config
    mkdir $p.saved
    (^rsync -a --delete --prune-empty-dirs --include 'FFXIV*.cfg' --include 'FFXIV_CHR*/' --include 'FFXIV_CHR*/*.DAT'
        --exclude '*' $"($p.config)/" ($p.saved | path join ffxivConfig))
    open --raw $p.launcher | lines | where not ($it | str starts-with "CurrentAccountId=") | to text
    | save --force ($p.saved | path join launcher.ini)
}
