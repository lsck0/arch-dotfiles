use module.nu *

export const meta = {packages: {pacman: [xivlauncher-bin]}, backup: {secrets: true}}

const XLCORE = ".xlcore"

def paths []: nothing -> record {
    let xl = $nu.home-dir | path join $XLCORE
    {
        xl: $xl, config: ($xl | path join ffxivConfig), launcher: ($xl | path join launcher.ini)
        saved: ($env.DOTFILES | path join secrets ffxiv)
    }
}

# seeded once from secrets, then the game's: it rewrites these files in place of a link or a managed copy
export def link [cfg: record] {
    let p = paths
    let unlocked = secret-is-plaintext ($p.saved | path join launcher.ini)
    if (which xivlauncher-core | is-empty) or not $unlocked { return [] }
    # the launcher's free-space check throws DriveNotFoundException while GamePath is missing (before an install)
    let game = if ($p.launcher | path exists) {
        open --raw $p.launcher | lines | parse "GamePath={path}" | get --optional 0.path
    } else { null }
    [
        (if ($p.config | path join FFXIV.cfg | path exists) { [] } else { step seed })
        (exec ffxiv-launcher [cp -n ($p.saved | path join launcher.ini) $p.launcher] --creates $p.launcher)
        (if ($game | is-empty) { [] } else { exec ffxiv-game-path [mkdir -p $game] --creates $game })
    ]
}

# no-clobber: keybinds or character data already there stay
export def seed []: nothing -> nothing {
    let p = paths
    mkdir $p.config
    ^cp -rnT ($p.saved | path join ffxivConfig) $p.config
    touch ($p.config | path join .from-secrets)
}

# chat logs, game backups, screenshots, .old rotations and the square enix login stay out
export def backup [cfg: record]: nothing -> nothing {
    let p = paths
    if not ($p.config | path join FFXIV.cfg | path exists) { error make {msg: $"no ($p.config)/FFXIV.cfg"} }
    secret-seed-guard ($p.config | path join .from-secrets) ($p.saved | path join ffxivConfig) $p.config
    mkdir $p.saved
    (^rsync -a --delete --prune-empty-dirs --include 'FFXIV*.cfg' --include 'FFXIV_CHR*/' --include 'FFXIV_CHR*/*.DAT'
        --exclude '*' $"($p.config)/" ($p.saved | path join ffxivConfig))
    open --raw $p.launcher | lines | where not ($it | str starts-with "CurrentAccountId=") | str join "\n" | $"($in)\n"
    | save --force ($p.saved | path join launcher.ini)
}
