#!/usr/bin/env -S nu --no-config-file
# What the secrets checkout's backup commit refuses: a changed file outside git-crypt's keys/ and state/ and outside a
# module dir would be stored unencrypted. And sync-pull's signature gate: origin's head is merged only when the key
# bootstrap.sh pins signed it; a head nobody signed, one another key signed, and one whose signer is the key in the
# pinned file but not the pinned fingerprint are refused with the checkout left where it was. Root runs what a pull
# brings in, so this is the check that decides it.
use sync.nu [secrets-stray sync-pull]
use std/assert

const KEY_FILE = "signing.pub.asc"

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

def signature-cases [work: path]: nothing -> nothing {
    let owner = key-create owner
    let other = key-create other
    let origin = $work | path join origin.git
    let author = $work | path join author
    let checkout = $work | path join checkout
    ^git init --quiet --bare --initial-branch master $origin
    ^git clone --quiet $origin $author err> /dev/null
    git $author checkout --quiet -B master
    ^gpg --batch --armor --export $owner | save ($author | path join $KEY_FILE)
    $"SIGNING_KEY_FINGERPRINT=($owner)\nSIGNING_KEY_FILE=($KEY_FILE)\n" | save ($author | path join bootstrap.sh)
    origin-commit $author first $owner | ignore
    ^git clone --quiet $origin $checkout

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

def main []: nothing -> nothing {
    stray-cases
    # short: gpg-agent's socket path has to fit sun_path
    let work = mktemp --directory --tmpdir dot-sync-XXXXXX
    let gnupg = $work | path join gnupg
    mkdir $gnupg
    chmod 700 $gnupg
    let outcome = try {
        with-env {GNUPGHOME: $gnupg, GIT_CONFIG_GLOBAL: /dev/null, GIT_CONFIG_SYSTEM: /dev/null, DOT_RUN_FILE: "", FAILURES_FILE: ""} {
            let checked = try { signature-cases $work; null } catch {|e| $e }
            ^gpgconf --kill all | complete | ignore
            if $checked != null { error make $checked }
        }
        null
    } catch {|e| $e }
    rm --recursive --force $work
    if $outcome != null { error make $outcome }
}
