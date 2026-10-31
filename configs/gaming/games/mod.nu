use module.nu *

# links into ~/sync depend on what syncthing and the launcher created since, not on any input
export const meta = {
    volatile: true
    packages: {
        pacman: [
            curseforge heroic-games-launcher-bin kpat minecraft-launcher path-of-building-community-git r2modman-bin
            rcon-cli
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
    let busy = (^pgrep -x pobfrontend | complete).exit_code == 0
    let relink = ($p.pob_synced | path exists) and not $busy and ($p.pob | path type) != symlink
    if $relink { step relocate } else { [] }
}

export def relocate []: nothing -> nothing {
    let p = paths
    # dot never fills ~/sync: a local dir that holds builds stays for a manual merge
    if ($p.pob | path exists) and (ls $p.pob | is-not-empty) {
        print $"note: games: ($p.pob) holds builds; merge them into ($p.pob_synced) by hand, then rerun"
        return
    }
    if ($p.pob | path exists) { rm $p.pob }
    mkdir ($p.pob | path dirname)
    ^ln -s $p.pob_synced $p.pob
}
