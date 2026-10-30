#!/usr/bin/env -S nu --no-config-file -I @DOTFILES@/scripts/lib
# knock (base/nftables/fw-inbound.nft), then ssh to the real sshd on base/ssh's port; 22 is a tarpit

const REPO = "@DOTFILES@"
use secrets.nu [secret-is-plaintext]

const KNOCK = [@KNOCK@]
const PORT = "@PORT@"
const SSH_DEFAULT_PORT = "22"
const PROBE_TIMEOUT_S = 2
const KNOCK_TRIES = 5

# Knock, then ssh to [user@]<host> on the hidden port; the remaining arguments go to ssh.
def --wrapped main [target: string, ...args: string]: nothing -> nothing {
    if $target in ["-h" "--help"] { print $"usage: sshk [user@]<host> [ssh args...]: knock, then ssh to the hidden port ($PORT)"; return }
    let config = ^ssh -G $target | lines | split column --number 2 " " key value
    let host = $config | where key == hostname | get 0.value
    # a host with its own Port in ~/.ssh/config keeps it; ssh -G cannot tell an explicit 22 from the default
    let own_port = $config | where key == port | get 0.value
    let port = if $own_port == $SSH_DEFAULT_PORT { $PORT } else { $own_port }
    for _ in 1..$KNOCK_TRIES {
        ^knock $host ...($KNOCK | each { into string })
        if (do { ^nc -z -w $PROBE_TIMEOUT_S $host $port } | complete).exit_code == 0 { break }
    }
    let keys = [($REPO | path join configs secrets keys ssh_privatekey.asc) ($nu.home-dir | path join .ssh id_ed25519_sk)]
        | where { secret-is-plaintext $in }
    let ids = $keys | each { [-i $in] } | flatten
    let only = if ($keys | is-empty) { [] } else { [-o IdentitiesOnly=yes] }
    exec ssh -p $port ...$ids ...$only $target ...$args
}
