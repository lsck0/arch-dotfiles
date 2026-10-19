use log.nu *
use state.nu [LIB_DIR nu-bin]
use ledger.nu [ledger-get ledger-set]

const MIGRATION_FILE = '^(\d{4})-[a-z0-9-]+\.nu$'
const SYSTEM_LAYER = 'export const layer = "system"'

export def migrations-list [repo: path]: nothing -> table<id: string, file: path, layer: string, reversible: bool> {
    let dir = $repo | path join migrations
    if not ($dir | path exists) { return [] }
    ls $dir | where ($it.name | path basename) =~ $MIGRATION_FILE | sort-by name | each {|f|
        let text = open --raw $f.name
        {
            id: ($f.name | path basename | str replace ".nu" "")
            file: $f.name
            layer: (if ($text | str contains $SYSTEM_LAYER) { "system" } else { "user" })
            reversible: ($text =~ '(?m)^export def down\b')
        }
    }
}

export def migrations-pending [repo: path, layer: string]: nothing -> table {
    let applied = ledger-get migration
    migrations-list $repo | where layer == $layer and id not-in $applied
}

export def migration-run [m: record, direction: string]: nothing -> nothing {
    log-info $"migration ($m.id) ($direction)" {kind: migration, target: $m.id}
    ^(nu-bin) --no-config-file -I $LIB_DIR -c $"use ($m.file | to nuon) [($direction)]; ($direction)"
    let applied = ledger-get migration
    ledger-set migration (if $direction == "up" { $applied | append $m.id } else { $applied | where $it != $m.id })
}

export def migrations-run [repo: path, layer: string, --baseline]: nothing -> list<string> {
    let pending = migrations-pending $repo $layer
    if $baseline {
        ledger-set migration (ledger-get migration | append $pending.id)
        return $pending.id
    }
    for m in $pending { migration-run $m up }
    $pending.id
}
