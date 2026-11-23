#!/usr/bin/env -S nu --no-config-file
# secret-is-plaintext decides every rollout that reads keys/: only a file that exists and lacks git-crypt's header
# counts. secret-seed-guard's three branches: a marker (secret-seed-mark's) passes, live state the repo never seeded
# fails, and a clean start sets the marker. secret-path names keys/ or state/ only. secrets-keys-chmod closes keys/ and
# its private files, dotfiles included.
use secrets.nu [secret-is-plaintext secret-path secret-seed-guard secret-seed-mark secrets-keys-chmod]
use std/assert

const GITCRYPT_BLOB = 0x[00 47 49 54 43 52 59 50 54 00 9a 3c]

def plaintext-cases [work: path]: nothing -> nothing {
    let locked = $work | path join locked
    let plain = $work | path join plain
    let empty = $work | path join empty
    let short = $work | path join short
    $GITCRYPT_BLOB | save --raw $locked
    "token\n" | save $plain
    "" | save $empty
    $GITCRYPT_BLOB | first 4 | save --raw $short
    let cases = [
        [name file plaintext];
        ["a locked blob" $locked false]
        ["a plaintext file" $plain true]
        ["an empty file" $empty true]
        ["a file shorter than the header" $short true]
        ["a missing file" ($work | path join missing) false]
    ]
    for c in $cases { assert equal (secret-is-plaintext $c.file) $c.plaintext $c.name }
}

def seed-cases [work: path]: nothing -> nothing {
    let witness = $work | path join live state.db
    mkdir ($witness | path dirname)

    let clean = $work | path join clean
    secret-seed-guard $clean $witness
    assert ($clean | path join .from-secrets | path exists) "no live state: the marker was not set"

    touch $witness
    secret-seed-guard $clean $witness
    let seeded = $work | path join seeded
    secret-seed-mark $seeded
    secret-seed-guard $seeded $witness

    let unseeded = $work | path join unseeded
    let message = try { secret-seed-guard $unseeded $witness; "" } catch {|e| $e.msg }
    assert ($message | str contains $"($unseeded) was not seeded from secrets") $"live state without a marker: ($message | to nuon)"
    assert (not ($unseeded | path exists)) "live state without a marker: the marker was set"
}

def path-cases []: nothing -> nothing {
    with-env {DOTFILES: /repo} {
        assert equal (secret-path keys syncthing host) /repo/configs/secrets/keys/syncthing/host
        assert equal (secret-path state ffxiv) /repo/configs/secrets/state/ffxiv
        assert ((try { secret-path secrets x; "" } catch {|e| $e.msg }) | str contains "none of keys, state") "another kind"
    }
}

def mode [file: path]: nothing -> string { ^stat --format=%a $file | str trim }

def chmod-cases [work: path]: nothing -> nothing {
    let secrets = $work | path join secrets
    let keys = $secrets | path join keys
    mkdir ($keys | path join host sshkeydir)
    let files = [
        [file mode];
        [token "600"] [host/sshkeydir/.ed25519.sk "600"] [id.pub "644"] [pgp-public.asc "644"]
    ]
    for f in $files {
        touch ($keys | path join $f.file)
        ^chmod 644 ($keys | path join $f.file)
    }
    ^chmod 755 $keys
    secrets-keys-chmod $secrets
    assert equal (mode $keys) "700" "keys/"
    for f in $files { assert equal (mode ($keys | path join $f.file)) $f.mode $f.file }
    secrets-keys-chmod ($work | path join absent)
}

def main []: nothing -> nothing {
    let work = mktemp --directory
    let outcome = try { plaintext-cases $work; seed-cases $work; path-cases; chmod-cases $work; null } catch {|e| $e }
    rm --recursive --force $work
    if $outcome != null { error make $outcome }
}
