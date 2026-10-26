# Migrations run once per machine and layer; `export const layer = "system"` makes one root's.

use log.nu *
use state.nu [LIB_DIR nu-bin]
use ledger.nu [ledger-get ledger-set]

const MIGRATION_FILE = '^(\d{4})-[a-z0-9-]+\.nu$'
const SYSTEM_LAYER = 'export const layer = "system"'

def migrations-list [repo: path]: nothing -> table<id: string, file: path, layer: string> {
    let dir = $repo | path join migrations
    if not ($dir | path exists) { return [] }
    ls $dir | where ($it.name | path basename) =~ $MIGRATION_FILE | sort-by name | each {|f|
        let text = open --raw $f.name
        {
            id: ($f.name | path basename | str replace ".nu" "")
            file: $f.name
            layer: (if ($text | str contains $SYSTEM_LAYER) { "system" } else { "user" })
        }
    }
}

export def migrations-pending [repo: path, layer: string]: nothing -> table {
    let applied = ledger-get migration
    migrations-list $repo | where layer == $layer and id not-in $applied
}

# Runs a migration's up and records it applied.
def migration-run [m: record]: nothing -> nothing {
    log-info $"migration ($m.id)" {kind: migration, target: $m.id}
    ^(nu-bin) --no-config-file -I $LIB_DIR -c $"use ($m.file | to nuon) [up]; up"
    ledger-set migration (ledger-get migration | append $m.id)
}

# A layer's first run baselines every migration; its initialised marker keeps it from looking fresh later.
export def migrations-run [repo: path, layer: string, --baseline]: nothing -> list<string> {
    let pending = migrations-pending $repo $layer
    let initialised = ledger-get initialised
    let fresh = $layer not-in $initialised and (ledger-get migration | is-empty)
    if $layer not-in $initialised { ledger-set initialised ($initialised | append $layer) }
    if $baseline or $fresh {
        ledger-set migration (ledger-get migration | append $pending.id)
        return $pending.id
    }
    for m in $pending { migration-run $m }
    $pending.id
}
