#!/usr/bin/env -S nu --no-config-file

const ROUTER = "@ROUTER@"
const PC = "@HOST@"
const KNOCK = [@KNOCK@]
const PORT = "@PORT@"
const PROBE_TIMEOUT_S = 2
const TRIES = 45
const TRY_INTERVAL = 2sec

def main []: nothing -> nothing {
    ^ssh -o ConnectTimeout=5 $"root@($ROUTER)" wol-pc
    print --stderr $"wake-pc: magic packet sent, waiting for ($PC) ..."
    # knock every try: it only opens the sshd port once the desktop's firewall is loaded
    for _ in 1..$TRIES {
        ^knock $PC ...($KNOCK | each { into string })
        if (do { ^nc -z -w $PROBE_TIMEOUT_S $PC $PORT } | complete).exit_code == 0 { exec sshk $PC }
        sleep $TRY_INTERVAL
    }
    print --stderr $"wake-pc: ($PC) did not answer ssh within ~3min"
    exit 1
}
