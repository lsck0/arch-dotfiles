use module.nu *

# links into ~/sync depend on what syncthing and the launcher created since, not on any input
export const meta = {packages: {pacman: [modrinth-app sqlite]}, backup: {secrets: true}, volatile: true}

const LOGIN_TABLES = [minecraft_users modrinth_users minecraft_device_tokens]

def paths []: nothing -> record {
    let data = xdg data ModrinthApp
    let saved = secret-path keys modrinth
    {
        data: $data, db: ($data | path join app.db), seed: (host-seed $saved app.db), saved: (host-file $saved app.db)
        saves: ($nu.home-dir | path join sync games mc saves)
    }
}

# a profile whose synced saves dir syncthing already delivered: dot only links to it, never creates or fills it
def unlinked [p: record]: nothing -> list<path> {
    glob ($p.data | path join profiles *) --no-file | where {|profile|
        let live = $profile | path join saves
        ($live | path type) != symlink and ($p.saves | path join ($profile | path basename) | path exists)
    }
}

export def link [cfg: record] {
    if (which modrinth-app | is-empty) { return [] }
    let p = paths
    let busy = process-running 'java|modrinth-app'
    let relocate = (profile-has secrets) and (platform-has homelab) and ($p.saves | path exists) and not $busy and (unlinked $p | is-not-empty)
    [
        # seeded once: modrinth rewrites app.db in place
        (if (secret-is-plaintext $p.seed) { step seed --creates $p.db })
        (step relocate --done=(not $relocate))
    ]
}

export def seed []: nothing -> nothing {
    let p = paths
    mkdir $p.data
    ^cp -n $p.seed $p.db
    secret-seed-mark $p.data
}

export def relocate []: nothing -> nothing {
    let p = paths
    for profile in (unlinked $p) {
        let live = $profile | path join saves
        let synced = $p.saves | path join ($profile | path basename)
        if ($live | path exists) and (ls $live | is-not-empty) {
            print $"note: modrinth: ($live) has worlds and ($synced) exists: merge them by hand, then dot apply links it"
            continue
        }
        rm --recursive --force $live   # absent or empty, checked above
        ^ln -s $synced $live
    }
}

# The login alone decides a new copy: the launcher rewrites the other tables (caches, instances) on every start, and
# each copy is the whole database in the secrets repo's history. Immutable for the saved copy: a plain open of a wal
# database leaves -shm and -wal files beside it.
def logins [db: string]: nothing -> record {
    ^sqlite3 $db ...($LOGIN_TABLES | each { $"select * from ($in) order by 1" }) | complete | select exit_code stdout
}

export def backup [cfg: record]: nothing -> nothing {
    let p = paths
    if (which modrinth-app | is-empty) or not ($p.db | path exists) { return }
    secret-seed-guard $p.data $p.seed
    let live = logins $"file:($p.db)?mode=ro"
    if $live.exit_code == 0 and $live == (logins $"file:($p.saved)?immutable=1") { return }
    sqlite-snapshot $p.db $p.saved
}
