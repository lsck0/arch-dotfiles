#!/usr/bin/env -S nu --no-config-file
# a backup keeps opening with whatever passphrase it held: after removing a leaked one, overwrite every older copy

const REPO = path self | path expand | path dirname | path join ../../../.. | path expand
use ($REPO | path join scripts lib usage.nu) [die]
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext]

const STAGE_KEY_FILE = "/etc/cryptsetup-keys.d/root.key"

def main []: nothing -> nothing {
    let secrets = $REPO | path join configs secrets keys
    if not (secret-is-plaintext ($secrets | path join pgp_privatekey.asc)) { die "secrets is locked, unlock it first" }
    let root = ^findmnt -n -o SOURCE / | str trim | split row "[" | first
    if not ($root | str starts-with /dev/mapper/) { die "/ is not on a LUKS mapping" }
    let part = ^lsblk -lnso NAME,TYPE $root | lines | split column --regex '\s+' name type | where type == part
    if ($part | is-empty) { die $"no partition under ($root)" }
    let device = $"/dev/($part.0.name)"
    let name = $"luks-header-(open --raw /etc/hostname | str trim).img"
    let dest = $secrets | path join $name
    if not (^git -C $secrets check-attr filter -- $name | str trim | str ends-with ": filter: git-crypt") {
        die $"configs/secrets/.gitattributes does not git-crypt ($name)"
    }
    # the stage keyfile's slot would ride along, and that key may still sit in freed ESP blocks
    if (^sudo test -e $STAGE_KEY_FILE | complete).exit_code == 0 {
        die "the stage keyfile is still armed, run this after the stage chain"
    }
    let tmp = ^sudo mktemp -d | str trim
    let failed = try {
        ^sudo cryptsetup luksHeaderBackup $device --header-backup-file $"($tmp)/header.img"
        ^sudo cat $"($tmp)/header.img" | ^install -m600 /dev/stdin $dest
        null
    } catch {|e| $e.msg }
    ^sudo rm -rf $tmp
    if $failed != null { die $failed }
    if (^cryptsetup luksDump $dest | complete).exit_code != 0 { die $"($dest) is no LUKS header" }
    print $"header-backup: ($device) -> ($dest), commit secrets to keep it off this disk"
}
