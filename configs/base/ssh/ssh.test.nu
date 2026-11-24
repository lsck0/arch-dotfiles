#!/usr/bin/env -S nu --no-config-file
# Host keys pinned from the secrets: each pinned key lands in the host key dir as a 600 copy with its 644 public half,
# rekeyed only when one changed; with none pinned the apply names the backup command, but only when unlocked.

use std/assert
use mod.nu [host-keys-install]

const KEYS = [ssh_host_ed25519_key ssh_host_ecdsa_key]

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
        assert ($copy | path exists) $"($what): ($k) not installed"
        assert equal (open --raw $copy) (open --raw ($src | path join $k)) $"($what): ($k) is not the pinned key"
        assert equal (mode $copy) "rw-------" $"($what): ($k) is (mode $copy)"
        assert equal (mode $"($copy).pub") "rw-r--r--" $"($what): ($k).pub is (mode $"($copy).pub")"
        let public = ^ssh-keygen -y -f ($src | path join $k) | str trim
        assert equal (open --raw $"($copy).pub" | str trim) $public $"($what): ($k).pub is not its public half"
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
    assert ($first.rekeyed and $first.note == null) $"first pin: ($first | to nuon)"
    installed-check "first pin" $src $dest
    let again = host-keys-install $src $dest $backup
    assert not $again.rekeyed "unchanged keys rekeyed"

    # sshd's own generated key under a pinned name is replaced
    keygen ($dest | path join ssh_host_ecdsa_key) ecdsa
    let changed = host-keys-install $src $dest $backup
    assert $changed.rekeyed "a changed key did not rekey"
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
        assert not $r.rekeyed $"($c.what): rekeyed"
        assert equal ($r.note != null) $c.note $"($c.what): note ($r.note | to nuon)"
        assert (not $c.note or ($r.note | str contains $"mkdir -p ($backup)")) $"($c.what): the note names no backup: ($r.note)"
    }

    # sshk's help, which a wrapped main gets as a glob, answers with its usage instead of a conversion error
    let repo = $env.FILE_PWD | path join .. .. .. | path expand
    let sshk = $dir | path join sshk
    open --raw ($env.FILE_PWD | path join scripts sshk.nu)
    | str replace --all "@DOTFILES@" $repo | str replace --all "@PORT@" "2222" | str replace --all "@KNOCK@" "1 2 3"
    | save $sshk
    for flag in [--help -h] {
        let r = ^$nu.current-exe --no-config-file -I ($repo | path join scripts lib) $sshk $flag | complete
        assert ($r.exit_code == 0 and ($r.stdout | str starts-with "usage: sshk")) $"sshk ($flag): ($r.stderr | str trim)"
    }
    rm --recursive --force $dir
}
