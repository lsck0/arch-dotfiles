use module.nu *

export const meta = {
    packages: {
        pacman: [
            curseforge heroic-games-launcher-bin kpat minecraft-launcher path-of-building-community-git r2modman-bin
            rcon-cli
        ]
    }
}

def paths []: nothing -> record {
    {
        pob: ($nu.home-dir | path join .local share pobfrontend "Path of Building" Builds)
        pob_synced: ($nu.home-dir | path join sync games pob)
    }
}

export def link [cfg: record] {
    let p = paths
    # pobfrontend rewrites a build on save, so relinking under it would drop whatever it holds open
    let busy = ps | where name =~ pobfrontend | is-not-empty
    let relink = ($p.pob_synced | path exists) and not $busy and ($p.pob | path type) != symlink
    if $relink { step relocate } else { [] }
}

export def relocate []: nothing -> nothing {
    let p = paths
    if ($p.pob | path exists) and ($p.pob_synced | path exists) {
        # -n: never overwrite a synced copy
        ^cp -rn $"($p.pob)/." $"($p.pob_synced)/"
        let kept = $"($p.pob).pre-sync.(date now | format date '%s')"
        mv $p.pob $kept
        print $"note: games: merged builds into ($p.pob_synced), the old copy kept as ($kept | path basename)"
    } else if ($p.pob | path exists) {
        mv $p.pob $p.pob_synced
    }
    # pobfrontend's data dir does not exist until it has run once
    mkdir ($p.pob | path dirname)
    ^ln -s $p.pob_synced $p.pob
}
