# shellcheck shell=bash
# helpers for configs/secrets, a git-crypt worktree that is a GITCRYPT blob while locked

# secret_is_plaintext <file>: file exists, is readable, and is not a locked git-crypt blob
secret_is_plaintext() {
    local file="$1" magic
    [[ -r "$file" ]] || return 1
    # locked git-crypt files begin with the bytes "\0GITCRYPT"
    magic=$(head -c 9 "$file" 2>/dev/null | tr -d '\0')
    [[ "$magic" != GITCRYPT ]]
}
