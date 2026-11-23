# git-crypt plaintext checks and the owner gate.

use profile.nu [profile-has profile-owner]

const GITCRYPT_MAGIC = 0x[00 47 49 54 43 52 59 50 54]
export const OWNER_WITNESS = "configs/secrets/keys/pgp/private.asc"
const KEYS_PUBLIC = ['*.pub' '*public*']
const SECRET_KINDS = [keys state]
# in a dir the repo seeded from secrets: a backup from it carries no unseeded live state over the repo's
export const SECRET_SEED_MARKER = ".from-secrets"

# Whether the bytes are a locked git-crypt blob (those start with "\0GITCRYPT").
export def secret-bytes-locked []: binary -> bool {
    $in | bytes starts-with $GITCRYPT_MAGIC
}

# True when the file exists and is not a locked git-crypt blob.
export def secret-is-plaintext [file: path]: nothing -> bool {
    if not ($file | path exists) { return false }
    not (open --raw $file | first ($GITCRYPT_MAGIC | bytes length) | into binary | secret-bytes-locked)
}

# Whether configs/secrets/ is fetched and unlocked: a profile with secrets; as root the caller decided.
export def secrets-wanted []: nothing -> bool {
    (is-admin) or (profile-has secrets)
}

# The full owner gate: the secrets profile is selected AND the owner's YubiKey has unlocked it. Personal config and
# credentials roll out only when both hold; the profile alone leaves a generic desktop.
export def owner-unlocked []: nothing -> bool {
    (profile-has secrets) and (secret-is-plaintext ($env.DOTFILES | path join $OWNER_WITNESS))
}

# The owner gate of a system verb, which reads no profile: an owner login is recorded and the secrets are unlocked.
# Root sees that in the secrets it was handed (a locked one is never streamed), a user planning the system layer in
# the checkout's witness.
export def owner-system-unlocked []: nothing -> bool {
    if not (profile-owner) { return false }
    let handed = $env.DOTFILES_SECRETS? | default ""
    if $handed != "" { return (glob ($handed | path join "**" "*") --no-dir | is-not-empty) }
    secret-is-plaintext ($env.DOTFILES | path join $OWNER_WITNESS)
}

# The streamed root secret, or a path that never exists without the secrets.
export def system-secret [...parts: string]: nothing -> path {
    $env.DOTFILES_SECRETS? | default --empty "/nonexistent" | path join ...$parts
}

# keys/ and every private file in it readable by the owner alone, dotfiles included: git checks them out 644.
export def secrets-keys-chmod [secrets: path]: nothing -> nothing {
    let keys = $secrets | path join keys
    if not ($keys | path exists) { return }
    ^chmod 700 $keys
    ^find $keys -type f ...($KEYS_PUBLIC | each { [! -name $in] } | flatten) -exec chmod 600 '{}' +
}

# The repo's secret of app under configs/secrets/<keys|state>, parts below it.
export def secret-path [kind: string, app: string, ...parts: string]: nothing -> path {
    if $kind not-in $SECRET_KINDS { error make {msg: $"secret-path: ($kind) is none of ($SECRET_KINDS | str join ', ')"} }
    $env.DOTFILES | path join configs secrets $kind $app ...$parts
}

# Marks dir as seeded from secrets, which lets secret-seed-guard pass its backups.
export def secret-seed-mark [dir: path]: nothing -> nothing {
    mkdir $dir
    touch ($dir | path join $SECRET_SEED_MARKER)
}

# Before a backup: live state at witness that the repo never seeded into dir would overwrite the repo's, so fail;
# without live state dir is marked.
export def secret-seed-guard [dir: path, witness: path]: nothing -> nothing {
    let marker = $dir | path join $SECRET_SEED_MARKER
    if ($marker | path exists) { return }
    if ($witness | path exists) {
        error make {msg: $"($dir) was not seeded from secrets; dot apply --user seeds it, or touch ($marker) to keep the live state"}
    }
    secret-seed-mark $dir
}
