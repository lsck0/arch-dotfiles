#!/usr/bin/env bash

# windows owns kernel, boot, drivers, power, audio and network under wsl; nothing here applies
[[ "$FORM_FACTOR" != wsl ]] || exit 0

install -Dm644 config /etc/endlessh/config
dropin_install endlessh.service override.conf || true

# sshd only moves off 22 once authorized_keys exists
if sshd -T 2>/dev/null | grep -qi '^port 22$'; then
    echo "endlessh: sshd still on 22, not starting the tarpit (add SSH keys and rerun)" >&2
else
    systemctl enable --now endlessh.service
fi
