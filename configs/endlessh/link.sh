#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
if ! command -v endlessh >/dev/null 2>&1; then
    exit 0
fi
set -ex
sudo install -Dm644 config /etc/endlessh/config
sudo install -Dm644 override.conf /etc/systemd/system/endlessh.service.d/override.conf
sudo systemctl daemon-reload
# Only take port 22 once real sshd has moved off it (configs/ssh applies Port 2222
# only when authorized_keys exists), else the two collide on a keyless fresh machine.
if sudo sshd -T 2>/dev/null | grep -qi '^port 22$'; then
    echo "endlessh: sshd still on 22; not starting the tarpit (add SSH keys + rerun)" >&2
else
    sudo systemctl enable --now endlessh.service
fi
