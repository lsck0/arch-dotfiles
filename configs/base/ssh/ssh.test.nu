#!/usr/bin/env -S nu --no-config-file
# Host keys pinned from the secrets: each pinned key lands in the host key dir as a 600 copy with its 644 public half,
# rekeyed only when one changed; with none pinned the apply names the backup command, but only when unlocked.

use mod.nu [host-keys-install]

const KEYS = [ssh_host_ed25519_key ssh_host_ecdsa_key]

def fail [msg: string] { error make {msg: $"ssh.test: ($msg)"} }

def keygen [file: path, type: string]: nothing -> nothing {
    rm --force $file $"($file).pub"
    ^ssh-keygen -q -t $type -N "" -C "" -f $file
    rm $"($file).pub"
}

def mode [file: path]: nothing -> string {
    ls --long $file | get 0.mode
}

# What install made of dest: each pinned key's copy is the source, 600, its .pub 644 and the source's public half.
def installed-check [what: string, src: path, dest: path]: nothing -> nothing {
    for k in $KEYS {
        let copy = $dest | path join $k
        if not ($copy | path exists) { fail $"($what): ($k) not installed" }
        if (open --raw $copy) != (open --raw ($src | path join $k)) { fail $"($what): ($k) is not the pinned key" }
        if (mode $copy) != "rw-------" { fail $"($what): ($k) is (mode $copy)" }
        if (mode $"($copy).pub") != "rw-r--r--" { fail $"($what): ($k).pub is (mode $"($copy).pub")" }
        let public = ^ssh-keygen -y -f ($src | path join $k) | str trim
        if (open --raw $"($copy).pub" | str trim) != $public { fail $"($what): ($k).pub is not its public half" }
    }
}

def main [] {
    if (which ssh-keygen install | length) < 2 { print --stderr "ssh.test: skipped: needs ssh-keygen and install"; return }
    let dir = mktemp --directory --tmpdir dot-ssh-test-XXXXXX
    let src = $dir | path join pinned
    let dest = $dir | path join etc-ssh
    let backup = $dir | path join backup
    mkdir $src $dest
    keygen ($src | path join ssh_host_ed25519_key) ed25519
    keygen ($src | path join ssh_host_ecdsa_key) ecdsa

    let first = host-keys-install $src $dest $backup
    if not $first.rekeyed or $first.note != null { fail $"first pin: ($first | to nuon)" }
    installed-check "first pin" $src $dest
    let again = host-keys-install $src $dest $backup
    if $again.rekeyed { fail "unchanged keys rekeyed" }

    # sshd's own generated key under a pinned name is replaced
    keygen ($dest | path join ssh_host_ecdsa_key) ecdsa
    let changed = host-keys-install $src $dest $backup
    if not $changed.rekeyed { fail "a changed key did not rekey" }
    installed-check "changed key" $src $dest

    let none = $dir | path join none
    mkdir $none
    let cases = [
        [what backup note];
        ["none pinned, unlocked" $backup true]
        ["none pinned, locked" null false]
    ]
    for c in $cases {
        let r = host-keys-install $none $dest $c.backup
        if $r.rekeyed { fail $"($c.what): rekeyed" }
        if ($r.note != null) != $c.note { fail $"($c.what): note ($r.note | to nuon)" }
        if $c.note and not ($r.note | str contains $"mkdir -p ($backup)") { fail $"($c.what): the note names no backup: ($r.note)" }
    }
    rm --recursive --force $dir
}
