use module.nu *

export const meta = {packages: {pacman: [xivlauncher-bin]}, backup: {secrets: true}}

const XLCORE = ".xlcore"

def paths []: nothing -> record {
    let xl = $nu.home-dir | path join $XLCORE
    let saved = $env.DOTFILES | path join configs secrets state ffxiv
    {
        xl: $xl, config: ($xl | path join ffxivConfig), launcher: ($xl | path join launcher.ini)
        seed: {config: (host-seed $saved ffxivConfig), launcher: (host-seed $saved launcher.ini)}
        saved: (host-file $saved)
    }
}

# Seeded once: the game rewrites these files in place.
export def link [cfg: record] {
    let p = paths
    let launcher = desktop-override XIVLauncher.desktop {
        $in | str replace --all --regex '(?m)^Exec=' 'Exec=env MANGOHUD=1 '
    }
    let unlocked = secret-is-plaintext $p.seed.launcher
    if (which xivlauncher-core | is-empty) or not $unlocked { return $launcher }
    # the launcher's free-space check throws DriveNotFoundException while GamePath is missing (before an install)
    let game = if ($p.launcher | path exists) {
        open --raw $p.launcher | lines | parse "GamePath={path}" | get --optional 0.path
    } else { null }
    [
        $launcher
        (if ($p.config | path join FFXIV.cfg | path exists) { [] } else { step seed })
        (exec ffxiv-launcher [cp -n $p.seed.launcher $p.launcher] --creates $p.launcher)
        (if ($game | is-empty) { [] } else { exec ffxiv-game-path [mkdir -p $game] --creates $game })
    ]
}

export def seed []: nothing -> nothing {
    let p = paths
    mkdir $p.config
    ^cp -rnT $p.seed.config $p.config
    touch ($p.config | path join .from-secrets)
}

export def backup [cfg: record]: nothing -> nothing {
    let p = paths
    if not ($p.config | path join FFXIV.cfg | path exists) { error make {msg: $"no ($p.config)/FFXIV.cfg"} }
    secret-seed-guard ($p.config | path join .from-secrets) $p.seed.config $p.config
    mkdir $p.saved
    (^rsync -a --delete --prune-empty-dirs --include 'FFXIV*.cfg' --include 'FFXIV_CHR*/' --include 'FFXIV_CHR*/*.DAT'
        --exclude '*' $"($p.config)/" ($p.saved | path join ffxivConfig))
    open --raw $p.launcher | lines | where not ($it | str starts-with "CurrentAccountId=") | str join "\n" | $"($in)\n"
    | save --force ($p.saved | path join launcher.ini)
}
