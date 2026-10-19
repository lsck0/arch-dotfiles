const GITCRYPT_MAGIC = 0x[00 47 49 54 43 52 59 50 54]

# a locked git-crypt file starts with "\0GITCRYPT"
export def secret-is-plaintext [file: path]: nothing -> bool {
    if not ($file | path exists) { return false }
    (open --raw $file | first 9 | into binary) != $GITCRYPT_MAGIC
}

# before a backup pulls live state into secrets: live state the repo never seeded would overwrite the repo's
export def secret-seed-guard [marker: path, witness: path, label: string]: nothing -> nothing {
    if ($marker | path exists) { return }
    if ($witness | path exists) {
        error make {msg: $"($label) was not seeded from secrets; dot apply --user it, or touch ($marker) to keep the live state"}
    }
    mkdir ($marker | path dirname)
    touch $marker
}
