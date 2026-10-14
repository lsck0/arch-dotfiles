#!/usr/bin/env -S nu --no-config-file
# knock (base/nftables/fw-inbound.nft), then ssh to the real sshd on 2222; 22 is a tarpit

const REPO = path self | path expand | path dirname | path join .. .. .. | path expand
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext]

const KNOCK = [9003 7001 8002]
const PORT = 2222
const PROBE_TIMEOUT_S = 2
# knock sends each syn once; one lost packet on wifi keeps 2222 shut
const KNOCK_TRIES = 5

# Knock, then ssh to [user@]<host> on the hidden port; the remaining arguments go to ssh.
def --wrapped main [target: string, ...args: string]: nothing -> nothing {
    let host = $target | split row "@" | last
    for _ in 1..$KNOCK_TRIES {
        ^knock $host ...($KNOCK | each { into string })
        if (do { ^nc -z -w $PROBE_TIMEOUT_S $host $PORT } | complete).exit_code == 0 { break }
    }
    # neither is in ssh's default key paths
    let keys = [($REPO | path join secrets ssh_privatekey.asc) ($nu.home-dir | path join .ssh id_ed25519_sk)]
        | where { secret-is-plaintext $in }
    let ids = $keys | each { [-i $in] } | flatten
    let only = if ($keys | is-empty) { [] } else { [-o IdentitiesOnly=yes] }
    exec ssh -p $PORT ...$ids ...$only $target ...$args
}
