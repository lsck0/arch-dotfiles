use module.nu *

export const meta = {
    packages: {pacman: [taskwarrior-tui timew]}
    inputs: [/usr/share/doc/timew/ext/on-modify.timewarrior]
}

export const options = {
    sync_url: {
        type: string?
        default: null
        doc: "The taskchampion server every replica syncs with as the one client of configs/secrets/keys/taskwarrior-*; none: no sync"
        label: "Sync server"
    }
    recurrence: {
        type: bool
        default: true
        doc: "This replica creates the instances of recurring tasks; one per sync, or each adds its own copy (task-sync(5))"
        label: "Create recurring tasks"
        scope: machine
    }
}

const HOOK = "/usr/share/doc/timew/ext/on-modify.timewarrior"
const CLIENT_ID = "configs/secrets/keys/taskwarrior-client-id"
const SECRET = "configs/secrets/keys/taskwarrior-encryption-secret"
const SYNC_RC = ".config/task/sync.taskrc"

def secret-read [file: path]: nothing -> string {
    open --raw $file | str trim --right
}

# Taskwarrior refuses a missing include: locked secrets keep the file as it is, else empty.
def sync-text [cfg: record]: nothing -> string {
    let rc = $nu.home-dir | path join $SYNC_RC
    if $cfg.sync_url == null { return "" }
    let id = $env.DOTFILES | path join $CLIENT_ID
    let secret = $env.DOTFILES | path join $SECRET
    if (secret-is-plaintext $id) and (secret-is-plaintext $secret) {
        [
            $"sync.server.url=($cfg.sync_url)"
            $"sync.server.client_id=(secret-read $id)"
            $"sync.encryption_secret=(secret-read $secret)"
            ...(if $cfg.recurrence { [] } else { [recurrence=off] })
        ] | str join "\n" | $"($in)\n"
    } else {
        if (profile-has secrets) { log-warn $"task: no readable ($CLIENT_ID) or ($SECRET), keeping the sync config as it is" }
        if ($rc | path exists) { open --raw $rc } else { "" }
    }
}

export def link [cfg: record] {
    let sync = sync-text $cfg
    let bugwarrior = (profile-has secrets) and (which bugwarrior | is-not-empty)
    [
        (file-copy taskrc ($nu.home-dir | path join .config task taskrc))
        (file-copy wal.theme ($nu.home-dir | path join .config task wal.theme))
        (if ($HOOK | path exists) { file-copy $HOOK ($nu.home-dir | path join .task hooks on-modify.timewarrior) --mode 755 } else { [] })
        (if $bugwarrior { [] } else { file-text ($nu.home-dir | path join .config bugwarrior uda.taskrc) "" })
        (file-text ($nu.home-dir | path join $SYNC_RC) $sync --mode 600)
        (if ($sync | is-empty) { [] } else { (unit-file task-sync.service) ++ (unit-file task-sync.timer --enable --now) })
    ]
}
