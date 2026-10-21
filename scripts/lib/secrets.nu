use profile.nu [profile-has]

const GITCRYPT_MAGIC = 0x[00 47 49 54 43 52 59 50 54]

# True when the file exists and is not a locked git-crypt blob (those start with "\0GITCRYPT").
export def secret-is-plaintext [file: path]: nothing -> bool {
    if not ($file | path exists) { return false }
    (open --raw $file | first 9 | into binary) != $GITCRYPT_MAGIC
}

# Whether configs/secrets/ is fetched and unlocked: a profile with secrets; as root the caller decided.
export def secrets-wanted []: nothing -> bool {
    (is-admin) or (profile-has secrets)
}

# Before a backup: live state at witness that the repo never seeded (no marker) would overwrite the repo's, so fail.
export def secret-seed-guard [marker: path, witness: path, label: string]: nothing -> nothing {
    if ($marker | path exists) { return }
    if ($witness | path exists) {
        error make {msg: $"($label) was not seeded from secrets; dot apply --user it, or touch ($marker) to keep the live state"}
    }
    mkdir ($marker | path dirname)
    touch $marker
}
