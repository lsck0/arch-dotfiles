#!/usr/bin/env bash

SOPS_KEYS="${HOME}/.config/sops/age/keys.txt"

if profile_has identity; then
    # ssh tries id_ed25519_sk by default, after the agent's keys; skipped while no key is plugged in
    mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
    for stub in ssh-*; do
        [[ -f "$stub" && "$stub" != *.pub ]] || continue
        # a copy: ssh rejects a key file other users can read, and git checks out 0644
        # through file_update: a person's own id_ed25519_sk is preserved, never overwritten
        file_update "$stub" "${HOME}/.ssh/id_ed25519_sk" 600 || true
        file_update "${stub}.pub" "${HOME}/.ssh/id_ed25519_sk.pub" 644 || true
        break
    done
fi

# sops' default identities: the file key once secrets are unlocked, then every enrolled YubiKey (touch)
if profile_has secrets; then
    # built aside and placed through file_update: age keys a person added by hand are preserved, not truncated away
    tmp=$(mktemp)
    if grep -qs '^AGE-SECRET-KEY-' "$DOTFILES/secrets/age.txt"; then
        cat "$DOTFILES/secrets/age.txt" >>"$tmp"
    fi
    # no YubiKey enrolled yet means no identity files
    cat age-*.identity >>"$tmp" 2>/dev/null || true
    file_update "$tmp" "$SOPS_KEYS" 600 || true
    rm -f "$tmp"
fi
