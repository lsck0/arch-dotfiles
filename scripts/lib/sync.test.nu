#!/usr/bin/env -S nu --no-config-file
# What the secrets checkout's backup commit refuses: a changed file outside git-crypt's keys/, the plaintext state/ and
# a module dir would be stored unencrypted, and so would a staged file under keys/ that git-crypt did not encrypt. And
# sync-pull's signature gate: origin's head is merged only when the key bootstrap.sh pins signed it; a head nobody
# signed, one another key signed, and one whose signer is the key in the pinned file but not the pinned fingerprint
# are refused with the checkout left where it was. Root runs what a pull brings in, so this is the check that decides
# it, for the secrets checkout too: it moves only onto a revision a signed generation names.
use sync.nu [secrets-stray secrets-changed secrets-staged-clear secrets-push secrets-fast-forward sync-pull]
use std/assert

const KEY_FILE = "signing.pub.asc"
const GITLINK = "configs/secrets"
const GITCRYPT_BLOB = 0x[00 47 49 54 43 52 59 50 54 00 01 02]
const UNNAMED = "secrets origin holds commits no signed generation names"

def stray-cases []: nothing -> nothing {
    let modules = [shell work]
    let cases = [
        [name changed stray];
        ["credentials and app state" [keys/token state/app/db.json] []]
        ["git-crypt's own files" [.git-crypt/keys/default .gitattributes] []]
        ["a module's files" [shell/mod.nu shell/aliases.zsh work/sub/unit.conf] []]
        ["a file at the top" [notes.txt] [notes.txt]]
        ["a dir that is no module" [scratch/token] [scratch/token]]
        ["a file named like a module" [shell] [shell]]
        ["a look-alike of keys" [keys.bak/token] [keys.bak/token]]
        ["mixed" [keys/a stray.env shell/mod.nu other/x] [stray.env other/x]]
    ]
    for c in $cases { assert equal (secrets-stray $c.changed $modules) $c.stray $"stray ($c.name)" }
    assert equal (secrets-stray [shell/mod.nu] []) [shell/mod.nu] "stray: a dir without a mod.nu counts as a module"
}

def --wrapped git [dir: path, ...args: string]: nothing -> string {
    ^git -C $dir -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@localhost -c gpg.program=gpg ...$args
}

def key-create [name: string]: nothing -> string {
    ^gpg --batch --quiet --pinentry-mode loopback --passphrase "" --quick-generate-key $"($name) <($name)@localhost>" ed25519 sign never
    ^gpg --batch --with-colons --list-keys $"($name)@localhost" | lines | where ($it | str starts-with "fpr:") | first | split row ":" | get 9
}

def head [dir: path]: nothing -> string { git $dir rev-parse HEAD | str trim }

# A commit on origin's master, signed by signer (null: unsigned), made in the author clone and pushed.
def origin-commit [author: path, text: string, signer: any]: nothing -> string {
    $"($text)\n" | save --force ($author | path join file)
    git $author add --all
    let sign = if $signer == null { [--no-gpg-sign] } else { [$"--gpg-sign=($signer)"] }
    git $author commit --quiet ...$sign --message $text
    git $author push --quiet origin master
    head $author
}

def refused [checkout: path]: nothing -> string {
    try { sync-pull $checkout; "" } catch {|e| $e.msg }
}

# A bare origin whose first generation the owner signed and pins, and the clone that authors its next ones.
def origin-create [work: path, name: string, owner: string]: nothing -> record<origin: path, author: path> {
    let origin = $work | path join $"($name).git"
    let author = $work | path join $"($name)-author"
    ^git init --quiet --bare --initial-branch master $origin
    ^git clone --quiet $origin $author err> /dev/null
    git $author checkout --quiet -B master
    ^gpg --batch --armor --export $owner | save ($author | path join $KEY_FILE)
    $"SIGNING_KEY_FINGERPRINT=($owner)\nSIGNING_KEY_FILE=($KEY_FILE)\n" | save ($author | path join bootstrap.sh)
    origin-commit $author first $owner | ignore
    {origin: $origin, author: $author}
}

def signature-cases [work: path, owner: string, other: string]: nothing -> nothing {
    let made = origin-create $work origin $owner
    let author = $made.author
    let checkout = $work | path join checkout
    ^git clone --quiet $made.origin $checkout

    let signed = origin-commit $author signed $owner
    sync-pull $checkout
    assert equal (head $checkout) $signed "a head the pinned key signed was not merged"

    for c in [[name signer]; ["unsigned" null] ["signed by another key" $other]] {
        origin-commit $author $c.name $c.signer | ignore
        let message = refused $checkout
        assert ($message | str contains $"is not signed by ($owner)") $"($c.name): ($message | to nuon)"
        assert equal (head $checkout) $signed $"($c.name): the checkout moved"
    }

    # the pinned file now holds the other key, the pinned fingerprint still names the owner: a good signature of the
    # wrong key
    ^gpg --batch --armor --export $other | save --force ($checkout | path join $KEY_FILE)
    let message = refused $checkout
    assert ($message | str contains $"is not signed by ($owner)") $"another key in the pinned file: ($message | to nuon)"
    assert equal (head $checkout) $signed "another key in the pinned file: the checkout moved"
    git $checkout checkout --quiet -- $KEY_FILE

    let mended = origin-commit $author mended $owner
    sync-pull $checkout
    assert equal (head $checkout) $mended "a signed head after refused ones was not merged"

    git $checkout checkout --quiet --detach
    assert (refused $checkout | str contains "HEAD is not on master") "a detached HEAD pulled"
}

# A commit in a secrets clone, pushed to its origin unless local.
def secrets-commit [clone: path, name: string, --local]: nothing -> string {
    $"($name)\n" | save ($clone | path join $name)
    git $clone add --all
    git $clone commit --quiet --message $name
    if not $local { git $clone push --quiet origin HEAD:master }
    head $clone
}

# A generation on the dotfiles origin that names the secrets revision, signed by signer (null: unsigned).
def generation [author: path, secrets_sha: string, signer: any]: nothing -> nothing {
    git $author update-index --add --cacheinfo $"160000,($secrets_sha),($GITLINK)"
    let sign = if $signer == null { [--no-gpg-sign] } else { [$"--gpg-sign=($signer)"] }
    git $author commit --quiet ...$sign --message $"names ($secrets_sha)"
    git $author push --quiet origin master | ignore
}

def contains [clone: path, sha: string]: nothing -> bool {
    (git $clone merge-base --is-ancestor $sha HEAD | complete).exit_code == 0
}

def push-refused [checkout: path, secrets: path]: nothing -> string {
    try { secrets-push $checkout $secrets; "" } catch {|e| $e.msg }
}

# Machine a syncs, then machine b: b adopts a's secrets commit because a's signed generation names it. A commit that
# only reached the secrets origin, and one an unsigned generation names, are never adopted.
def secrets-cases [work: path, owner: string]: nothing -> nothing {
    let made = origin-create $work dotfiles $owner
    let secrets_origin = $work | path join secrets.git
    ^git init --quiet --bare --initial-branch master $secrets_origin
    let a = $work | path join secrets-a
    ^git clone --quiet $secrets_origin $a err> /dev/null
    git $a checkout --quiet -B master
    generation $made.author (secrets-commit $a base) $owner
    let checkout = $work | path join machine-b
    ^git clone --quiet $made.origin $checkout
    let b = $checkout | path join $GITLINK
    ^git clone --quiet $secrets_origin $b
    let intruder = $work | path join secrets-intruder
    ^git clone --quiet $secrets_origin $intruder

    let from_a = secrets-commit $a from-a
    generation $made.author $from_a $owner
    secrets-commit $b from-b --local | ignore
    secrets-push $checkout $b
    assert (contains $b $from_a) "a secrets commit a signed generation names was not adopted"
    assert equal (git $secrets_origin rev-parse master | str trim) (head $b) "the rebased backup was not pushed"

    git $a pull --quiet --rebase origin master
    let next_a = secrets-commit $a next-a
    generation $made.author $next_a $owner
    git $intruder pull --quiet --rebase origin master
    let unnamed = secrets-commit $intruder unnamed
    ^git -C $checkout fetch --quiet --no-recurse-submodules origin
    secrets-fast-forward $checkout $b
    assert equal (head $b) $next_a "the fast-forward did not stop at the revision the signed generation names"

    # another sync pushed its secrets but not yet its generation: with nothing of b's own to push, b's sync goes on
    let message = push-refused $checkout $b
    assert equal $message "" "no commit of b's own behind an unnamed one: the push refused"
    assert equal (head $b) $next_a "no commit of b's own behind an unnamed one: the checkout moved"

    let backup = secrets-commit $b backup --local
    let message = push-refused $checkout $b
    assert ($message | str contains $UNNAMED) $"an unnamed secrets commit: ($message | to nuon)"
    assert equal (head $b) $backup "an unnamed secrets commit: the checkout moved"

    generation $made.author $unnamed null
    let message = push-refused $checkout $b
    assert ($message | str contains $"is not signed by ($owner)") $"an unsigned generation: ($message | to nuon)"
    assert equal (head $b) $backup "an unsigned generation: the checkout moved"
    assert (not (contains $b $unnamed)) "a secrets commit no signed generation names was adopted"
}

# A new file that is already staged counts as changed, a deletion does not; of the staged files under keys/ only the
# ones without git-crypt's header are reported.
def backup-cases [work: path]: nothing -> nothing {
    let repo = $work | path join backup
    ^git init --quiet --initial-branch master $repo
    mkdir ($repo | path join keys) ($repo | path join state)
    "old\n" | save ($repo | path join state gone)
    "old\n" | save ($repo | path join state kept)
    git $repo add --all
    git $repo commit --quiet --message first
    rm ($repo | path join state gone)
    "new\n" | save --force ($repo | path join state kept)
    "token\n" | save ($repo | path join staged.env)
    git $repo add staged.env
    "note\n" | save ($repo | path join untracked.txt)
    assert equal (secrets-changed $repo | sort) [staged.env state/kept untracked.txt] "changed files"

    $GITCRYPT_BLOB | save --raw ($repo | path join keys locked)
    "token\n" | save ($repo | path join keys clear)
    "" | save ($repo | path join keys empty)
    git $repo add --all
    assert equal (secrets-staged-clear $repo | sort) [keys/clear keys/empty] "staged files under keys/ in clear"
}

def main []: nothing -> nothing {
    stray-cases
    # short: gpg-agent's socket path has to fit sun_path
    let work = mktemp --directory --tmpdir dot-sync-XXXXXX
    let gnupg = $work | path join gnupg
    mkdir $gnupg
    chmod 700 $gnupg
    let outcome = try {
        # sync.nu's own git calls carry no -c: a rebase needs a committer
        let identity = {GIT_AUTHOR_NAME: test, GIT_AUTHOR_EMAIL: test@localhost, GIT_COMMITTER_NAME: test, GIT_COMMITTER_EMAIL: test@localhost}
        with-env ({GNUPGHOME: $gnupg, GIT_CONFIG_GLOBAL: /dev/null, GIT_CONFIG_SYSTEM: /dev/null, DOT_RUN_FILE: "", FAILURES_FILE: ""} | merge $identity) {
            let checked = try {
                backup-cases $work
                let owner = key-create owner
                signature-cases $work $owner (key-create other)
                secrets-cases $work $owner
                null
            } catch {|e| $e }
            ^gpgconf --kill all | complete | ignore
            # the keyring's socket dir under the runtime dir outlives its home otherwise
            ^gpgconf --remove-socketdir | complete | ignore
            if $checked != null { error make $checked }
        }
        null
    } catch {|e| $e }
    rm --recursive --force $work
    if $outcome != null { error make $outcome }
}
