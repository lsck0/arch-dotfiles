use module.nu *

export const meta = {
    packages: {pacman: [syncthing]}
    inputs: [~/.local/state/syncthing/cert.pem ~/.local/state/syncthing/key.pem ~/sync/.stignore]
}

const STATE = ".local/state/syncthing"
const IDENTITY = [[file mode]; [config.xml 600] [cert.pem 644] [key.pem 600]]
const GUI_SECRET = "secrets/syncthing-gui-password"
const NAS_NAME = "vm-104-nas"
const API_WAIT_SECONDS = 30
const GUI_TRIES = 3
const PASSWORD_SHAPE = '^[A-Za-z0-9+/=._~-]+$'
# repos under ~/sync carry a per-machine .identity/ (browser profiles, agent state, creds, caches): never replicated
const STIGNORE_LINE = "**/.identity"
const VERSIONS_MAX_AGE = 2592000
# borg's repo folder; configs/core/borg/borg-backup.nu has the same path and id
const BORG_FOLDER = ".local/share/borg-repo"

def secret-dir []: nothing -> path {
    $env.DOTFILES | path join secrets syncthing (sys host | get hostname)
}

def borg-id []: nothing -> string {
    $"borg-(sys host | get hostname)"
}

def st [...args: string]: nothing -> string {
    ^syncthing cli ...$args | str trim
}

# everything after this keeps the device private, so a daemon that never answers is a failure
def api-wait []: nothing -> nothing {
    let up = 1..$API_WAIT_SECONDS | each { $in } | any {|_|
        if (^syncthing cli show system | complete).exit_code == 0 { true } else { sleep 1sec; false }
    }
    if not $up { error make {msg: $"syncthing: the api did not answer in ($API_WAIT_SECONDS)s, settings not applied"} }
}

# .stignore is the one file in ~/sync the dotfiles touch (syncthing never syncs it): the line is added, edits kept
export def stignore []: nothing -> nothing {
    let file = $nu.home-dir | path join sync .stignore
    let lines = if ($file | path exists) { open --raw $file | lines } else { [] }
    if $STIGNORE_LINE not-in $lines { $lines | append $STIGNORE_LINE | str join "\n" | $"($in)\n" | save --force $file }
}

# before the daemon starts, so it comes up paired
export def identity-install []: nothing -> nothing {
    let state = $nu.home-dir | path join $STATE
    ^systemctl --user stop syncthing.service
    for f in $IDENTITY { ^install -D -m $f.mode (secret-dir | path join $f.file) ($state | path join $f.file) }
}

def gui-password []: nothing -> string {
    let secret = $env.DOTFILES | path join $GUI_SECRET
    if (secret-is-plaintext $secret) { return (open --raw $secret | str trim) }
    let generated = $nu.home-dir | path join $STATE gui-password
    if not ($generated | path exists) or (open --raw $generated | str trim | is-empty) {
        ^bash -c 'umask 077 && head -c 24 /dev/urandom | base64 > "$1"' gui $generated
        log-warn $"syncthing: no ($GUI_SECRET), generated the gui password into ($generated)"
    }
    open --raw $generated | str trim
}

# any local login could open the gui on 127.0.0.1 and read the api key from it; the password goes over stdin
def gui-login [user: string, password: string]: nothing -> nothing {
    if $password !~ $PASSWORD_SHAPE { error make {msg: "syncthing: the gui password may only hold base64 characters"} }
    # one call per setting with a wait after each: a gui change restarts the listener, and `syncthing cli -` sends
    # the next line into that refused window and still exits 0; the restart can lag the answer, so read it back
    let set = 1..$GUI_TRIES | each { $in } | any {|_|
        try { ^syncthing cli config gui user set $user }
        api-wait
        try { $"config gui password set ($password)\n" | ^syncthing cli - o+e>| ignore }
        api-wait
        sleep 1sec
        api-wait
        (st config gui user get) == $user and (st config gui password get | is-not-empty)
    }
    if not $set { error make {msg: "syncthing: the gui login did not stick, the gui is open to every local user"} }
}

# the only peer is static: no discovery, relays or port mapping, nothing phones home
export def api-config [paired: string]: nothing -> nothing {
    api-wait
    for option in [local-ann-enabled global-ann-enabled relays-enabled natenabled crenabled] {
        ^syncthing cli config options $option set false
    }
    ^syncthing cli config options uraccepted set -- -1
    gui-login (^id -un | str trim) (gui-password)
    let sync = $nu.home-dir | path join sync
    # no secrets: a fresh identity, paired by hand in the ui
    if $paired != "true" and "sync" not-in (st config folders list | lines) {
        let folder = {id: sync, label: sync, path: $sync, type: sendreceive, fsWatcherEnabled: true, ignorePerms: true}
        ^syncthing cli config folders add-json ($folder | to json --raw)
    }
    if "sync" in (st config folders list | lines) {
        # a delete or overwrite from another device keeps the old copy in .stversions for 30 days
        ^syncthing cli config folders sync versioning type set staggered
        ^syncthing cli config folders sync versioning params set maxAge ($VERSIONS_MAX_AGE | into string)
        if (st config folders sync versioning type get) != "staggered" {
            error make {msg: "syncthing: staggered versioning on sync did not stick"}
        }
    }
    borg-folder
}

# sent to the nas only; no versioning (a versioned repo keeps every replaced segment twice) and no watcher: borg-backup
# pauses the folder while it writes and the unpause rescans it
def borg-folder []: nothing -> nothing {
    let id = borg-id
    if $id not-in (st config folders list | lines) {
        let nas = st config devices list | lines | where {|d| (st config devices $d name get) == $NAS_NAME } | get --optional 0
        if $nas == null {
            log-warn $"syncthing: no device ($NAS_NAME) yet, ($id) not shared; borg backs up locally until it is"
            return
        }
        let me = st show system | from json | get myID
        let folder = {
            id: $id, label: $id, path: ($nu.home-dir | path join $BORG_FOLDER), type: sendonly, fsWatcherEnabled: false
            devices: [{deviceID: $me} {deviceID: $nas}]
        }
        ^syncthing cli config folders add-json ($folder | to json --raw)
        log-warn $"syncthing: shared ($id) with ($NAS_NAME), accept it there as receive-only without versioning"
    }
    ^syncthing cli config folders $id type set sendonly
    ^syncthing cli config folders $id fswatcher-enabled set false
    ^syncthing cli config folders $id versioning type set ''
}

export def link [cfg: record] {
    if not (profile-has homelab) { return [] }
    let state = $nu.home-dir | path join $STATE
    let secrets = secret-dir
    let paired = ["config.xml" "key.pem"] | all {|f| secret-is-plaintext ($secrets | path join $f) }
    # only a new or changed identity is installed, a matching one keeps its live config and transfers
    let differs = {|f| not ($state | path join $f | path exists) or (open --raw ($secrets | path join $f)) != (open --raw ($state | path join $f)) }
    let changed = $paired and (not ($state | path join config.xml | path exists) or ([cert.pem key.pem] | any $differs))
    [
        (step stignore)
        (if $changed { step identity-install } else { [] })
        # a background job, not an app: lowest cpu weight and priority
        (dropin syncthing.service 10-background.conf --then [systemctl --user try-restart syncthing.service])
        (unit-enable syncthing.service --now)
        (file-text ($nu.home-dir | path join $BORG_FOLDER .stignore) "lock.exclusive\nlock.roster\n")
        (step api-config ($paired | into string))
    ]
}
