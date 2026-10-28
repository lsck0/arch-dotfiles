use module.nu *

export const meta = {
    packages: {pacman: [gpg-tui]}
    inputs: [~/.gnupg/pubring.kbx ~/.gnupg/trustdb.gpg ~/.gnupg/private-keys-v1.d]
}

export const options = {
    cache_ttl: {
        type: int
        default: 600
        doc: "Seconds gpg-agent caches a passphrase after use before re-asking, gpg-agent.conf(5) default-cache-ttl"
        label: "Passphrase cache (s)"
        scope: user
    }
    cache_ttl_max: {
        type: int
        default: 7200
        doc: "Seconds gpg-agent caches a passphrase at most, however often it is used, gpg-agent.conf(5) max-cache-ttl"
        label: "Passphrase cache max (s)"
        scope: user
    }
}

const PRIVATE_KEY = "configs/secrets/keys/pgp_privatekey.asc"

def --wrapped gpg-ok [...args: string]: nothing -> bool {
    (^gpg --batch ...$args | complete).exit_code == 0
}

def public-key [fpr: string]: nothing -> list<path> {
    glob ($env.PWD | path join *.pub.asc) | where {|f| ^gpg --show-keys --with-colons $f | lines | any { $in == $"fpr:::::::::($fpr):" } }
}

def identity [fpr: string]: nothing -> list<record> {
    let private = $env.DOTFILES | path join $PRIVATE_KEY
    let has_secret = gpg-ok --list-secret-keys $fpr
    let trusted = ^gpg --export-ownertrust | lines | any { $in == $"($fpr):6:" }
    [
        (if (gpg-ok --list-keys $fpr) { [] } else { public-key $fpr | each { exec $"gpg-import ($in | path basename)" [gpg --batch --import $in] } })
        (if $trusted { [] } else { step gpg-trust $fpr })
        (if $has_secret or not (secret-is-plaintext $private) { [] } else { exec gpg-import-private [gpg --batch --import $private] })
        (if $has_secret { [] } else { step gpg-card-stubs })
    ] | decls-flatten
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
            # pinentry-qt needs Qt6/KF6, which only the desktop group installs; fall back to the generic wrapper when it is absent (wsl, headless)
            PINENTRY: (if ("/usr/bin/pinentry-qt" | path exists) { "/usr/bin/pinentry-qt" } else { "/usr/bin/pinentry" })
        }
            --then [gpgconf --reload gpg-agent])
        (file-copy scdaemon.conf ($dir | path join scdaemon.conf) --then [gpgconf --kill scdaemon])
        (file-text ($dir | path join gpg.conf) $"(open --raw gpg.conf)($default_key)" --mode 600)
        (if $fpr == "" { [] } else { identity $fpr })
    ]
}
