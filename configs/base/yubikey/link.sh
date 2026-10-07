#!/usr/bin/env bash

SOPS_KEYS="${HOME}/.config/sops/age/keys.txt"

if profile_has identity; then
    # pam_u2f registrations of every enrolled key (scripts/lib/yubikey.sh init), read from pam_u2f's per-user default
    if [[ -f u2f_keys ]]; then link_into "${HOME}/.config/Yubico" u2f_keys; fi

    # ssh tries id_ed25519_sk by default, after the agent's keys; skipped while no key is plugged in
    mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
    for stub in ssh-*; do
        [[ -f "$stub" && "$stub" != *.pub ]] || continue
        # a copy: ssh rejects a key file other users can read, and git checks out 0644
        install -m600 "$stub" "${HOME}/.ssh/id_ed25519_sk"
        install -m644 "${stub}.pub" "${HOME}/.ssh/id_ed25519_sk.pub"
        break
    done
fi

# sops' default identities: the file key once secrets are unlocked, then every enrolled YubiKey (touch)
if profile_has secrets; then
    mkdir -p "$(dirname "$SOPS_KEYS")"
    : >"$SOPS_KEYS"
    chmod 600 "$SOPS_KEYS"
    if grep -qs '^AGE-SECRET-KEY-' "$DOTFILES/secrets/age.txt"; then
        cat "$DOTFILES/secrets/age.txt" >>"$SOPS_KEYS"
    fi
    # no YubiKey enrolled yet means no identity files
    cat age-*.identity >>"$SOPS_KEYS" 2>/dev/null || true
fi
