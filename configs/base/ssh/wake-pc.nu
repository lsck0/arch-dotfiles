#!/usr/bin/env -S nu --no-config-file
# wake the homelab's desktop: the always-on lab router emits the magic packet with its `wol-pc`, then ssh in once it is
# up. needs the homelab reachable (at home, or the homelab tunnel up) and the desktop's firmware wake on lan enabled;
# the laptop's key must be authorized as root on the router

# rendered by mod.nu from its wake_router and wake_host options
const ROUTER = "@ROUTER@"
const PC = "@HOST@"
const KNOCK = [9003 7001 8002]
const PORT = 2222
const PROBE_TIMEOUT_S = 2
const TRIES = 45
const TRY_INTERVAL = 2sec

def main []: nothing -> nothing {
    ^ssh -o ConnectTimeout=5 $"root@($ROUTER)" wol-pc
    print --stderr $"wake-pc: magic packet sent, waiting for ($PC) ..."
    # up once its firewall is loaded and lets the knock open 2222
    for _ in 1..$TRIES {
        ^knock $PC ...($KNOCK | each { into string })
        if (do { ^nc -z -w $PROBE_TIMEOUT_S $PC $PORT } | complete).exit_code == 0 { exec sshk $PC }
        sleep $TRY_INTERVAL
    }
    print --stderr $"wake-pc: ($PC) did not answer ssh within ~3min"
    exit 1
}
