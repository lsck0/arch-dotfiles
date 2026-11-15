use module.nu *

# needs Qt6/KF6, which only the desktop group installs; the generic pinentry where it is absent (wsl, headless)
const PINENTRY_QT = "/usr/bin/pinentry-qt"
const PINENTRY = "/usr/bin/pinentry"

export const meta = {
    packages: {pacman: [gpg-tui]}
    inputs: [~/.gnupg/pubring.kbx ~/.gnupg/trustdb.gpg ~/.gnupg/private-keys-v1.d $PINENTRY_QT]
}

export const options = {
    cache_ttl: {
        type: int
        # a working day: the lock and suspend hook (desktop/hyprland's quickshell-lock-launch.nu) empties the cache, so it
        # lasts only as long as the session stays unlocked
        default: 28800
        doc: "Seconds gpg-agent caches a passphrase after use before re-asking, gpg-agent.conf(5) default-cache-ttl; a screen lock or suspend empties the cache"
        label: "Passphrase cache (s)"
        scope: user
    }
    cache_ttl_max: {
        type: int
        default: 86400
        doc: "Seconds gpg-agent caches a passphrase at most, however often it is used, gpg-agent.conf(5) max-cache-ttl"
        label: "Passphrase cache max (s)"
        scope: user
    }
}

const PRIVATE_KEY = "configs/secrets/keys/pgp/private.asc"
const PASSPHRASE = "configs/secrets/keys/pgp/passphrase"
# what pinentry stores under when "save in password manager" is ticked, and looks up before it asks
const KEYRING_SCHEMA = "org.gnupg.Passphrase"
const KEYRING_STORED_BY = "GnuPG Pinentry"
const KEYRING_TIMEOUT = "2s"

def --wrapped gpg-ok [...args: string]: nothing -> bool {
    (^gpg --batch ...$args | complete).exit_code == 0
}

def public-key [fpr: string]: nothing -> list<path> {
    glob ($env.PWD | path join *.pub.asc) | where {|f| ^gpg --show-keys --with-colons $f | lines | any { $in == $"fpr:::::::::($fpr):" } }
}

# The keygrips of the key and its subkeys; pinentry files a passphrase under each one it asked for.
def keygrips [fpr: string]: nothing -> list<string> {
    ^gpg --batch --with-colons --with-keygrip --list-keys $fpr | complete | get stdout | lines
    | parse --regex '^grp:+(?<grip>[0-9A-F]+):' | get grip
}

# Whether the login keyring holds a pinentry passphrase for every keygrip; search never asks to unlock a keyring.
def keyring-seeded [fpr: string]: nothing -> bool {
    let grips = keygrips $fpr
    if ($grips | is-empty) or (which secret-tool | is-empty) { return false }
    let found = ^timeout $KEYRING_TIMEOUT secret-tool search --all xdg:schema $KEYRING_SCHEMA | complete
    let listed = $"($found.stdout)\n($found.stderr)" | lines
    $grips | all {|grip| $"attribute.keygrip = n/($grip)" in $listed }
}

# Silent signing is the keyring's entry: seeded from the secrets copy where the owner keeps one, else pinentry's
# "save in password manager" box, ticked once per machine. An unattended run has no session keyring to store into.
def keyring-passphrase [fpr: string]: nothing -> any {
    if (keyring-seeded $fpr) { return null }
    if (secret-is-plaintext ($env.DOTFILES | path join $PASSPHRASE)) {
        return (if ($env.DOTFILES_UNATTENDED? | is-empty) { step gpg-keyring-seed $fpr })
    }
    step gpg-keyring-note --key $fpr
}

def identity [fpr: string]: nothing -> list {
    let private = $env.DOTFILES | path join $PRIVATE_KEY
    let has_secret = gpg-ok --list-secret-keys $fpr
    let trusted = ^gpg --export-ownertrust | lines | any { $in == $"($fpr):6:" }
    let listed = gpg-ok --list-keys $fpr
    [
        (public-key $fpr | each { exec $"gpg-import ($in | path basename)" [gpg --batch --import $in] --done=$listed })
        (step gpg-trust $fpr --done=$trusted)
        (if (secret-is-plaintext $private) { exec gpg-import-private [gpg --batch --import $private] --done=$has_secret })
        (step gpg-card-stubs --done=$has_secret)
        (keyring-passphrase $fpr)
    ]
}

export def gpg-keyring-seed [fpr: string]: nothing -> nothing {
    let passphrase = open --raw ($env.DOTFILES | path join $PASSPHRASE) | lines | first
    for grip in (keygrips $fpr) {
        let key = $"n/($grip)"
        $passphrase | ^timeout $KEYRING_TIMEOUT secret-tool store --label $"GnuPG: ($key)" xdg:schema $KEYRING_SCHEMA stored-by $KEYRING_STORED_BY keygrip $key
    }
}

export def gpg-keyring-note []: nothing -> nothing {
    print ("note: gnupg: the login keyring has no passphrase for the signing key, so gpg asks again after every screen "
        + $"lock: tick \"save in password manager\" in the next pinentry dialog, or keep the passphrase in ($PASSPHRASE)")
}

export def gpg-trust [fpr: string]: nothing -> nothing {
    $"($fpr):6:\n" | ^gpg --import-ownertrust
}

export def gpg-card-stubs []: nothing -> nothing {
    try { ^gpg --card-status o+e>| ignore }
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join .gnupg
    # the owner default-key points at a key that is only present when unlocked; do not write it on profile selection alone
    let fpr = if (owner-unlocked) { (profile-load).gpg_fingerprint } else { "" }
    let default_key = if $fpr == "" { "" } else { $"default-key ($fpr)\n" }
    [
        (exec gnupg-dir [install -d -m 700 $dir] --creates $dir)
        # reload keeps cached keys; scdaemon reads its config only at start
        (file-render gpg-agent.conf ($dir | path join gpg-agent.conf) {
            CACHE_TTL: $cfg.cache_ttl, CACHE_TTL_MAX: $cfg.cache_ttl_max
            PINENTRY: (if ($PINENTRY_QT | path exists) { $PINENTRY_QT } else { $PINENTRY })
        }
            --then [gpgconf --reload gpg-agent])
        (file-copy scdaemon.conf ($dir | path join scdaemon.conf) --then [gpgconf --kill scdaemon])
        (file-text ($dir | path join gpg.conf) $"(open --raw gpg.conf)($default_key)" --mode 600)
        (if $fpr != "" { identity $fpr })
    ]
}
