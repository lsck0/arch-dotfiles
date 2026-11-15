#!/usr/bin/env -S nu --no-config-file
# autologin-pam puts the loadkey line ahead of the keyring's auth line, so the keyring module finds the cached disk
# passphrase as the token; a stack without the keyring gets it last.

use mod.nu [autologin-pam]

const LOADKEY = "-auth      optional     pam_systemd_loadkey.so"
const PERMIT = "auth       required     pam_permit.so"
const KEYRING = "-auth      optional     pam_gnome_keyring.so"
const KEYRING_SESSION = "-session   optional     pam_gnome_keyring.so auto_start"
const ACCOUNT = "account    include      login"

const CASES = [
    [name stock want];
    ["ly's stock stack" [$PERMIT $KEYRING $ACCOUNT $KEYRING_SESSION] [$PERMIT $LOADKEY $KEYRING $ACCOUNT $KEYRING_SESSION]]
    ["no keyring auth line" [$PERMIT $ACCOUNT $KEYRING_SESSION] [$PERMIT $ACCOUNT $KEYRING_SESSION $LOADKEY]]
]

def main [] {
    let failed = $CASES | where {|c| (autologin-pam $c.stock | lines) != $c.want }
    for c in $failed { print --stderr $"ly.test: ($c.name): got (autologin-pam $c.stock)" }
    if ($failed | is-not-empty) { error make {msg: $"ly.test: ($failed | length) of ($CASES | length) cases failed"} }
}
