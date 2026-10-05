#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh
is_personal || exit 0

if ! command -v ykman >/dev/null 2>&1; then
    exit 0
fi

set -e

sudo install -Dm644 pcsc.rules /etc/polkit-1/rules.d/50-pcsc-wheel.rules
sudo install -Dm644 70-yubikey-hidraw.rules /etc/udev/rules.d/70-yubikey-hidraw.rules
sudo udevadm control --reload && sudo udevadm trigger --action=change --subsystem-match=hidraw
sudo systemctl enable --now pcscd.socket

# pam_u2f registrations of every enrolled key (scripts/yubikey.sh init)
if [[ -f u2f_keys ]]; then
    mkdir -p "${HOME}/.config/Yubico"
    ln -sfn "${PWD}/u2f_keys" "${HOME}/.config/Yubico/u2f_keys"
fi

# ssh tries id_ed25519_sk by default, after the agent's keys; skipped while no key is plugged in
mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
for stub in ssh-*; do
    [[ -f "$stub" && "$stub" != *.pub ]] || continue
    # a copy: ssh rejects a key file other users can read, and git checks out 0644
    install -m600 "$stub" "${HOME}/.ssh/id_ed25519_sk"
    install -m644 "${stub}.pub" "${HOME}/.ssh/id_ed25519_sk.pub"
    break
done

# sops' default identities: the file key once secrets are unlocked, then every enrolled YubiKey (touch)
SOPS_KEYS="${HOME}/.config/sops/age/keys.txt"
mkdir -p "$(dirname "$SOPS_KEYS")"
: >"$SOPS_KEYS"
chmod 600 "$SOPS_KEYS"
if grep -qs '^AGE-SECRET-KEY-' ../secrets/age.txt; then
    cat ../secrets/age.txt >>"$SOPS_KEYS"
fi
# no YubiKey enrolled yet means no identity files
cat age-*.identity >>"$SOPS_KEYS" 2>/dev/null || true
