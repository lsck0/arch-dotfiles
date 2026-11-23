#!/usr/bin/env -S nu --no-config-file -I @DOTFILES@/scripts/lib
# knock (base/nftables/fw-inbound.nft), then ssh to the real sshd on base/ssh's port; 22 is a tarpit. All over ipv4:
# fw-inbound's knock sets hold ipv4 addresses only

const REPO = "@DOTFILES@"
use secrets.nu [secret-is-plaintext]

const KNOCK = [@KNOCK@]
const PORT = "@PORT@"
const SSH_DEFAULT_PORT = "22"
const PROBE_TIMEOUT_S = 2
const KNOCK_TRIES = 5

# Knock, then ssh to [user@]<host> on the hidden port; the remaining arguments go to ssh.
def --wrapped main [target, ...args]: nothing -> nothing {
    # untyped: a wrapped main gets a leading - word (--help) as a glob, which a string parameter refuses
    let target = $target | into string
    if $target in ["-h" "--help"] { print $"usage: sshk [user@]<host> [ssh args...]: knock, then ssh to the hidden port ($PORT)"; return }
    let config = ^ssh -G $target | lines | split column --number 2 " " key value
    let host = $config | where key == hostname | get 0.value
    # a host with its own Port in ~/.ssh/config keeps it; ssh -G cannot tell an explicit 22 from the default
    let own_port = $config | where key == port | get 0.value
    let port = if $own_port == $SSH_DEFAULT_PORT { $PORT } else { $own_port }
    for _ in 1..$KNOCK_TRIES {
        ^knock -4 $host ...($KNOCK | each { into string })
        if (do { ^nc -4 -z -w $PROBE_TIMEOUT_S $host $port } | complete).exit_code == 0 { break }
    }
    let keys = [($REPO | path join configs secrets keys ssh/private.asc) ($nu.home-dir | path join .ssh id_ed25519_sk)]
        | where { secret-is-plaintext $in }
    let ids = $keys | each { [-i $in] } | flatten
    let only = if ($keys | is-empty) { [] } else { [-o IdentitiesOnly=yes] }
    exec ssh -4 -p $port ...$ids ...$only $target ...$args
}
