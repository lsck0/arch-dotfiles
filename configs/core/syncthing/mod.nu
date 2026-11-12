use module.nu *
use ../../../platforms/homelab.nu [HOMELAB]

export const meta = {
    inputs: [~/.local/state/syncthing/cert.pem ~/.local/state/syncthing/key.pem ~/sync/.stignore]
}

export const options = {
    nas_address: {
        type: string?
        default: $HOMELAB.nas.syncthing
        doc: "Address of the homelab NAS device (the lab's nas role); discovery is off, so this is how it is found"
        label: "NAS address"
    }
}

export def packages [cfg: record]: nothing -> record {
    {pacman: (if (profile-owner) { [syncthing] } else { [] })}
}

const IDENTITY = [[file mode]; [config.xml 600] [cert.pem 644] [key.pem 600]]
const GUI_SECRET = "configs/secrets/keys/syncthing-gui-password"
const API_WAIT_S = 30
const GUI_TRIES = 3
const PASSWORD_SHAPE = '^[A-Za-z0-9+/=._~-]+$'
const STIGNORE_LINE = "**/.identity"
const VERSIONS_MAX_AGE_S = 30 * 24 * 60 * 60
const NAS_NAME = '(^|-)nas$'

def secret-dir []: nothing -> path {
    $env.DOTFILES | path join configs secrets keys syncthing (sys host | get hostname)
}

def st [...args: string]: nothing -> string {
    ^syncthing cli ...$args | str trim
}

def api-wait []: nothing -> nothing {
    let up = 1..$API_WAIT_S | each { $in } | any {|_|
        if (^syncthing cli show system | complete).exit_code == 0 { true } else { sleep 1sec; false }
    }
    if not $up { error make {msg: $"syncthing: the api did not answer in ($API_WAIT_S)s, settings not applied"} }
}

def stignore-file []: nothing -> path {
    $nu.home-dir | path join sync .stignore
}

def stignore-lines []: nothing -> list<string> {
    if (stignore-file | path exists) { open --raw (stignore-file) | lines } else { [] }
}

# Adds the line to ~/sync/.stignore, keeping edits: the one file in ~/sync the dotfiles touch (it never syncs).
export def stignore []: nothing -> nothing {
    let lines = stignore-lines
    if $STIGNORE_LINE not-in $lines { $lines | append $STIGNORE_LINE | str join "\n" | $"($in)\n" | save --force (stignore-file) }
}

# Installs the device identity before the daemon starts, so it comes up paired.
export def identity-install []: nothing -> nothing {
    let state = xdg state syncthing
    ^systemctl --user stop syncthing.service
    for f in $IDENTITY { ^install -D -m $f.mode (secret-dir | path join $f.file) ($state | path join $f.file) }
}

# The file the gui password comes from: the secret when readable, else one generated on this machine.
def gui-password-file []: nothing -> path {
    let secret = $env.DOTFILES | path join $GUI_SECRET
    if (secret-is-plaintext $secret) { $secret } else { xdg state syncthing gui-password }
}

# Which password file api-config sets and its mtime: a rotated secret or a regenerated password differs.
def gui-version []: nothing -> string {
    let file = gui-password-file
    if not ($file | path exists) { return "" }
    $"($file) (ls --long $file | get 0.modified | format date '%+')"
}

def gui-password []: nothing -> string {
    let file = gui-password-file
    if $file != ($env.DOTFILES | path join $GUI_SECRET) and (not ($file | path exists) or (open --raw $file | str trim | is-empty)) {
        ^bash -c 'umask 077 && head -c 24 /dev/urandom | base64 > "$1"' gui $file
        log-warn $"syncthing: no ($GUI_SECRET), generated the gui password into ($file)"
    }
    open --raw $file | str trim
}

# Locks the gui, from which any local login could read the api key; the password goes over stdin.
def gui-login [user: string, password: string]: nothing -> nothing {
    if $password !~ $PASSWORD_SHAPE { error make {msg: "syncthing: the gui password may only hold base64 characters"} }
    # one call per setting, read back: a gui change restarts the listener and `cli -` silently loses the next line
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

export def api-config [paired: string, nas: string = ""]: nothing -> nothing {
    api-wait
    if $nas != "" {
        for id in (st config devices list | lines) {
            if (st config devices $id name get) =~ $NAS_NAME and (try { st config devices $id addresses 0 get } catch { "" }) != $nas {
                ^syncthing cli config devices $id addresses 0 set $nas
            }
        }
    }
    for option in [local-ann-enabled global-ann-enabled relays-enabled natenabled crenabled] {
        ^syncthing cli config options $option set false
    }
    ^syncthing cli config options uraccepted set -- -1
    gui-login (^id -un | str trim) (gui-password)
    let sync = $nu.home-dir | path join sync
    if $paired != "true" and "sync" not-in (st config folders list | lines) {
        let folder = {id: sync, label: sync, path: $sync, type: sendreceive, fsWatcherEnabled: true, ignorePerms: true}
        ^syncthing cli config folders add-json ($folder | to json --raw)
    }
    if "sync" in (st config folders list | lines) {
        ^syncthing cli config folders sync versioning type set staggered
        ^syncthing cli config folders sync versioning params set maxAge ($VERSIONS_MAX_AGE_S | into string)
        if (st config folders sync versioning type get) != "staggered" {
            error make {msg: "syncthing: staggered versioning on sync did not stick"}
        }
    }
}

export def link [cfg: record] {
    if not (owner-unlocked) or not (platform-has homelab) { return [] }
    let state = xdg state syncthing
    let secrets = secret-dir
    let paired = ["config.xml" "key.pem"] | all {|f| secret-is-plaintext ($secrets | path join $f) }
    let differs = {|f| not ($state | path join $f | path exists) or (open --raw ($secrets | path join $f)) != (open --raw ($state | path join $f)) }
    let changed = $paired and (not ($state | path join config.xml | path exists) or ([cert.pem key.pem] | any $differs))
    let nas = $cfg.nas_address | default ""
    # a new identity replaces config.xml, so its secrets are part of what api-config last set
    let identity = if $paired { [cert.pem key.pem config.xml] | each {|f| open --raw ($secrets | path join $f) | hash sha256 } } else { [] }
    let api_key = [(gui-version) $nas ($paired | into string) ($VERSIONS_MAX_AGE_S | into string) ...$identity] | str join "\n" | hash sha256
    [
        (step stignore --done=($STIGNORE_LINE in (stignore-lines)))
        (step identity-install --done=(not $changed))
        (dropin syncthing.service 10-background.conf --then [systemctl --user try-restart syncthing.service])
        (unit-enable syncthing.service --now)
        (step api-config ($paired | into string) $nas --key $api_key)
    ]
}
