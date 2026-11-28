use module.nu *

# links into ~/sync depend on what syncthing and the launcher created since, not on any input
export const meta = {
    volatile: true
    packages: {
        pacman: [
            curseforge heroic-games-launcher-bin kpat lua51-luautf8 minecraft-launcher path-of-building-community-git
            r2modman-bin rcon-cli vintagestory
        ]
    }
}

def paths []: nothing -> record {
    {
        pob: (xdg data pobfrontend "Path of Building" Builds)
        pob_synced: ($nu.home-dir | path join sync games pob)
    }
}

export def link [cfg: record] {
    let p = paths
    # pobfrontend rewrites a build on save, so relinking under it would drop whatever it holds open
    let busy = process-running pobfrontend
    let relink = ($p.pob_synced | path exists) and not $busy and ($p.pob | path type) != symlink
    [(step relocate --done=(not $relink))]
}

export def relocate []: nothing -> nothing {
    let p = paths
    sync-link $p.pob $p.pob_synced games
}
