#!/usr/bin/env bash
# the homelab share for every admin of a HOMELAB machine; the credentials are the admin's secret, streamed in as data

CRED=/etc/samba/homelab.cred
SECRET="$DOTFILES_SECRETS/samba-homelab"
UNITS=(mnt-homelab.automount mnt-homelab.mount)

# only the machine fact removes it: a run without secrets never undoes one with them
if [[ -z "$HOMELAB" ]]; then
    if [[ -e "$UNIT_DIR/mnt-homelab.mount" || -e "$UNIT_DIR/mnt-homelab.automount" || -e "$CRED" ]]; then
        systemctl disable --now "${UNITS[@]}" 2>/dev/null || true
        rm -f "$UNIT_DIR/mnt-homelab.mount" "$UNIT_DIR/mnt-homelab.automount" "$CRED"
        systemctl daemon-reload
    fi
    exit 0
fi

command -v mount.cifs >/dev/null 2>&1 || exit 0

# a mount.cifs credentials file and nothing else: a user name, a password, optionally a domain
if [[ -f "$SECRET" ]]; then
    if grep -qvE '^(username|password|domain)=' "$SECRET" || ! grep -q '^password=' "$SECRET"; then
        echo "nas: samba-homelab is not a username=/password=/domain= credentials file, keeping $CRED" >&2
        exit 1
    fi
    install -Dm600 -o root -g root "$SECRET" "$CRED"
fi

# no credentials, no mount: never fall back to a guest mount
if [[ ! -f "$CRED" ]]; then
    echo "nas: no samba-homelab secret yet, the homelab mount stays off" >&2
    exit 0
fi

mkdir -p /mnt/homelab
unit_install mnt-homelab.mount mnt-homelab.automount
systemctl enable mnt-homelab.automount
