#!/usr/bin/env bash

# windows owns kernel, boot, drivers, power, audio and network under wsl; nothing here applies
[[ "$FORM_FACTOR" != wsl ]] || exit 0

# real files in /etc, tor runs as its own user and must not depend on /home
install -Dm644 torrc /etc/tor/torrc
# vendored from edu4rdshl/tor-router, the package is not installed so no upgrade can restore its fail-open unit
changed=0
file_update tor-router /usr/local/bin/tor-router 755 && changed=1
# a running router keeps its old table until reloaded; start swaps the table in one transaction, never a gap in the clear
if ((changed)) && systemctl is-active -q tor-router.service; then
    /usr/local/bin/tor-router start
fi
# no Requires=tor.service, so a tor restart cannot tear the table down and let traffic out in the clear;
# tor stays on-demand: toron/toroff start tor-router.service, no boot-time tor.service
unit_install tor-router.service
