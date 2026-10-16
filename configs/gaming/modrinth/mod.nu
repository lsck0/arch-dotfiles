use module.nu *

export const meta = {packages: {pacman: [modrinth-app]}, backup: {secrets: true}}

def paths []: nothing -> record {
    let data = $nu.home-dir | path join .local share ModrinthApp
    {
        data: $data, db: ($data | path join app.db), saved: ($env.DOTFILES | path join secrets modrinth app.db)
        saves: ($nu.home-dir | path join sync games mc saves)
    }
}

def unlinked [p: record]: nothing -> list<path> {
    glob ($p.data | path join profiles *) --no-file | where {|profile|
        let live = $profile | path join saves
        let synced = $p.saves | path join ($profile | path basename)
        ($live | path type) != symlink and (($live | path exists) or ($synced | path exists))
    }
}

export def link [cfg: record] {
    if (which modrinth-app | is-empty) { return [] }
    let p = paths
    # launcher state (accounts, auth tokens, instances), seeded once; modrinth rewrites app.db in place with its -wal
    let seed = if (secret-is-plaintext $p.saved) and not ($p.db | path exists) { step seed } else { [] }
    # only into a saves dir syncthing made: one made here first collides with the real one it delivers
    let busy = ps | where name in [java modrinth-app] | is-not-empty
    let relocate = (profile-has homelab) and ($p.saves | path exists) and not $busy and (unlinked $p | is-not-empty)
    [$seed (if $relocate { step relocate } else { [] })]
}

export def seed []: nothing -> nothing {
    let p = paths
    mkdir $p.data
    ^cp -n $p.saved $p.db
    touch ($p.data | path join .from-secrets)
}

# one world on two machines at once becomes a syncthing conflict copy
export def relocate []: nothing -> nothing {
    let p = paths
    for profile in (unlinked $p) {
        let pack = $profile | path basename
        let live = $profile | path join saves
        let synced = $p.saves | path join $pack
        if ($live | path exists) and ($synced | path exists) {
            # both hold worlds: add the ones the synced tree lacks, never overwrite or delete a synced copy
            ^cp -rn $"($live)/." $"($synced)/"
            mv $live $"($live).pre-sync.(date now | format date '%s')"
            print $"note: modrinth: merged ($pack) worlds into ($synced), the old copy kept as saves.pre-sync.*"
        } else if ($live | path exists) {
            mv $live $synced
        }
        ^ln -s $synced $live
    }
}

# .backup checkpoints app.db's -wal into one consistent file
export def backup [cfg: record]: nothing -> nothing {
    let p = paths
    if (which modrinth-app | is-empty) or not ($p.db | path exists) { return }
    secret-seed-guard ($p.data | path join .from-secrets) $p.saved $p.data
    mkdir ($p.saved | path dirname)
    rm --force $p.saved
    ^sqlite3 $p.db $".backup '($p.saved)'"
}
