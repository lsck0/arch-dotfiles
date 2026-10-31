# The Proton apps' sign-ins, carried across a reinstall of the same machine: per app one tar of the session files
# under its state dir plus the Secret Service items it keeps beside them. Restored only where nothing of the app's
# session is live, so a newer sign-in is never replaced.

use ../../../../scripts/lib/secrets.nu [secret-is-plaintext]
use ../../../../scripts/lib/state.nu [xdg]

# files: under the app's state dir; items: the Secret Service search that finds its items
export const APPS = [
    {name: pass, dir: [config "Proton Pass"], files: ["Partitions/app/Cookies" "Partitions/app/Local Storage"], items: null}
    {name: mail, dir: [config "Proton Mail"], files: ["Partitions/app/Cookies" "Partitions/app/Local Storage"], items: null}
    {name: meet, dir: [config "Proton Meet"], files: [Cookies "Local Storage"], items: null}
    {
        name: authenticator, dir: [data me.proton.authenticator]
        files: [cookies databases localstorage mediakeys preferences.dat storage]
        items: {service: com.proton.authenticator}
    }
    {name: vpn, dir: null, files: [], items: {service: Proton}}
]
export const MARKER = "proton-sessions/restored"

const BUS = "org.freedesktop.secrets"
const SERVICE_PATH = "/org/freedesktop/secrets"
const SERVICE_IFACE = "org.freedesktop.Secret.Service"
const NO_OBJECT = "/"
const ITEMS_HELPER = path self keyring-items.py
const ITEMS_FILE = "items.json"
const FILES_DIR = "files"
const SQLITE_MAGIC = 0x[53 51 4c 69 74 65 20 66 6f 72 6d 61 74 20 33 00]
# rebuilt by the app at start, or a moving part of a live database that .backup folds in
const SKIPPED_NAMES = [LOCK LOG LOG.old]
const SKIPPED_SUFFIXES = [-wal -shm -journal]

def busctl-json [...args: string]: nothing -> any {
    ^busctl --user --json=short ...$args | from json | get data
}

def app-dir [app: record]: nothing -> any {
    if $app.dir == null { null } else { xdg $app.dir.0 $app.dir.1 }
}

def attributes-args [attributes: record]: nothing -> list<string> {
    $attributes | items {|key, value| [$key $value] } | flatten
}

# A running Secret Service with its default collection unlocked; never starts one, which outside a login would make
# a keyring the login password does not open.
export def keyring-ready []: nothing -> bool {
    let owned = try {
        busctl-json call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s $BUS | first
    } catch { false }
    if not $owned { return false }
    let collection = busctl-json call $BUS $SERVICE_PATH $SERVICE_IFACE ReadAlias s default | first
    if $collection == $NO_OBJECT { return false }
    not (busctl-json get-property $BUS $collection org.freedesktop.Secret.Collection Locked)
}

# The item paths matching attributes: [unlocked locked].
def keyring-search [attributes: record]: nothing -> list<list<string>> {
    let count = $attributes | columns | length | into string
    busctl-json call $BUS $SERVICE_PATH $SERVICE_IFACE SearchItems "a{ss}" $count ...(attributes-args $attributes)
}

# The items matching attributes, each {label, attributes, content_type, secret} with the secret base64.
export def keyring-items-load [attributes: record]: nothing -> list<record> {
    ^python3 -I $ITEMS_HELPER load ($attributes | to json --raw) | from json
}

export def keyring-items-save [items: list<record>]: nothing -> nothing {
    $items | to json --raw | ^python3 -I $ITEMS_HELPER save
}

def keyring-items-exist [attributes: record]: nothing -> bool {
    let found = keyring-search $attributes
    ($found.0 | is-not-empty) or ($found.1 | is-not-empty)
}

# Copies a file or tree, each SQLite database through .backup so a live one arrives whole.
def tree-copy [src: path, dest: path]: nothing -> nothing {
    let files = if ($src | path type) == file { [""] } else {
        ^find $src -type f -printf '%P\n' | lines
    }
    let skipped = {|name|
        let base = $name | path basename
        $base in $SKIPPED_NAMES or ($SKIPPED_SUFFIXES | any {|suffix| $base | str ends-with $suffix })
    }
    for file in ($files | where {|f| not (do $skipped $f) }) {
        let from = if $file == "" { $src } else { $src | path join $file }
        let to = if $file == "" { $dest } else { $dest | path join $file }
        mkdir ($to | path dirname)
        let head = open --raw $from | first ($SQLITE_MAGIC | bytes length) | into binary
        if $head == $SQLITE_MAGIC {
            ^sqlite3 $from $".backup '($to)'"
            ^chmod $"--reference=($from)" $to
        } else {
            ^cp --preserve=mode $from $to
        }
    }
}

# Runs body on a fresh private dir, removed afterwards even when body fails: it holds session copies.
def stage-with [body: closure]: nothing -> any {
    let stage = mktemp --directory --tmpdir-path ($env.XDG_RUNTIME_DIR? | default "/tmp")
    let outcome = try { {value: (do $body $stage)} } catch {|error| {error: $error} }
    ^rm -rf $stage
    if "error" in $outcome { error make $outcome.error.raw }
    $outcome.value
}

# Whether any part of the app's session is on this machine: one of its files or one of its items.
export def session-live [app: record]: nothing -> bool {
    let dir = app-dir $app
    let file_live = $dir != null and ($app.files | any {|f| $dir | path join $f | path exists })
    $file_live or ($app.items != null and (keyring-items-exist $app.items))
}

# Writes the app's session into archive; false when nothing of it is live. The archive is byte-stable for an
# unchanged session, so an idle app commits nothing.
export def session-backup [app: record, archive: path]: nothing -> bool {
    let dir = app-dir $app
    let files = if $dir == null { [] } else { $app.files | where {|f| $dir | path join $f | path exists } }
    let items = if $app.items == null { [] } else { keyring-items-load $app.items }
    if ($files | is-empty) and ($items | is-empty) { return false }
    let built = $"($archive).new"
    mkdir ($archive | path dirname)
    stage-with {|stage|
        for file in $files { tree-copy ($dir | path join $file) ($stage | path join $FILES_DIR $file) }
        if ($items | is-not-empty) { $items | to json | save ($stage | path join $ITEMS_FILE) }
        ^tar --create --file $built --directory $stage --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --format=gnu .
        ^chmod 600 $built
    }
    let same = ($archive | path exists) and ((open --raw $archive | hash sha256) == (open --raw $built | hash sha256))
    if $same { ^rm -f $built } else { ^mv -f $built $archive }
    true
}

# Restores one app from archive: none (no archive), locked (git-crypt still locked), waiting (its items need an
# unlocked keyring), live (a session is already here, kept) or restored.
export def session-restore [app: record, archive: path]: nothing -> string {
    if not ($archive | path exists) { return none }
    if not (secret-is-plaintext $archive) { return locked }
    if $app.items != null and not (keyring-ready) { return waiting }
    if (session-live $app) { return live }
    stage-with {|stage|
        ^tar --extract --file $archive --directory $stage --no-same-owner
        let items = $stage | path join $ITEMS_FILE
        if ($items | path exists) { keyring-items-save (open $items) }
        let files = $stage | path join $FILES_DIR
        let dir = app-dir $app
        if $dir != null and ($files | path exists) {
            mkdir $dir
            ^cp --recursive --no-clobber --preserve=mode $"($files)/." $dir
            # cp carries the stage dir's mode onto dir
            ^chmod 700 $dir
        }
    }
    "restored"
}

export def sessions-restore [archives: path]: nothing -> table {
    $APPS | each {|app| {app: $app.name, status: (session-restore $app ($archives | path join $"($app.name).tar"))} }
}

export def sessions-backup [archives: path]: nothing -> table {
    $APPS | each {|app|
        if $app.items != null and not (keyring-ready) {
            return {app: $app.name, status: "keyring locked, kept"}
        }
        let saved = session-backup $app ($archives | path join $"($app.name).tar")
        {app: $app.name, status: (if $saved { "saved" } else { "not signed in, kept" })}
    }
}

# Done once every app is restored, live or without an archive; a locked or waiting one keeps the login unit armed.
export def sessions-settled [statuses: table]: nothing -> bool {
    $statuses | all {|s| $s.status not-in [locked waiting] }
}
