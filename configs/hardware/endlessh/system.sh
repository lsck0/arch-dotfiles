#!/usr/bin/env bash

install -Dm644 config /etc/endlessh/config
install -Dm644 override.conf /etc/systemd/system/endlessh.service.d/override.conf
systemctl daemon-reload

# sshd only moves off 22 once authorized_keys exists
if sshd -T 2>/dev/null | grep -qi '^port 22$'; then
    echo "endlessh: sshd still on 22, not starting the tarpit (add SSH keys and rerun)" >&2
else
    systemctl enable --now endlessh.service
fi
