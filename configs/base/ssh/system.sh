#!/usr/bin/env bash

DROPIN=/etc/ssh/sshd_config.d/10-hardening.conf

# no host keys before sshd's first start, and sshd -t needs them
ssh-keygen -A
# hardened baseline for every machine: real sshd on knocked 2222, no password, no root password login, so a keyless
# user has no remote ssh surface (console login still works)
# a config sshd rejects never replaces the running one: the previous drop-in comes back and sshd is left alone
backup=$(mktemp)
had_dropin=0
if [[ -f "$DROPIN" ]]; then cp -p "$DROPIN" "$backup" && had_dropin=1; fi
install -Dm644 10-hardening.conf "$DROPIN"
if ! sshd -t; then
    if ((had_dropin)); then install -m644 "$backup" "$DROPIN"; else rm -f "$DROPIN"; fi
    rm -f "$backup"
    echo "ssh: sshd rejects 10-hardening.conf, kept the previous config" >&2
    exit 1
fi
rm -f "$backup"
systemctl enable sshd.service
systemctl reload-or-restart sshd
