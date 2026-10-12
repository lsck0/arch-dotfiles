# shellcheck shell=bash
# helpers for secrets, a git-crypt worktree that is a GITCRYPT blob while locked

# secret_is_plaintext <file>: file exists, is readable, and is not a locked git-crypt blob
secret_is_plaintext() {
    local file="$1" magic
    [[ -r "$file" ]] || return 1
    # locked git-crypt files begin with the bytes "\0GITCRYPT"
    magic=$(head -c 9 "$file" 2>/dev/null | tr -d '\0')
    [[ "$magic" != GITCRYPT ]]
}

# secret_require_unlocked <repo>: exit unless secrets is unlocked, a locked worktree would stage plaintext into GITCRYPT blobs
secret_require_unlocked() {
    secret_is_plaintext "$1/secrets/pgp_privatekey.asc" || { echo "secrets is locked, unlock it first" >&2; exit 1; }
}

# secret_seed_guard <marker> <witness> <label>: the one-time check a secrets backup makes before pulling live state in.
# no marker and the witness already in secrets means this live state was not seeded from it, so refuse to clobber it;
# else drop the marker so later runs know the live state is ours to back up
secret_seed_guard() {
    local marker="$1" witness="$2" label="$3"
    [[ -e "$marker" ]] && return 0
    [[ -e "$witness" ]] && { echo "$label was not seeded from secrets; run config.sh, or touch $marker to keep the live state" >&2; exit 1; }
    touch "$marker"
}
