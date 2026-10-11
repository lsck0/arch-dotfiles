#!/usr/bin/env bash
# Scheduled $HOME backup into the syncthing folder the NAS receives; only a homelab user has that NAS, a guest gets nothing.

command -v borg >/dev/null 2>&1 || exit 0

if profile_has homelab; then
    link_commands borg-backup.sh
    unit_install borg-backup.service borg-backup.timer
    systemctl --user enable borg-backup.timer
    secret_is_plaintext "$DOTFILES/secrets/borg-passphrase" \
        || echo "borg: no readable secrets/borg-passphrase, every run fails until there is one (README.md)" >&2
else
    systemctl --user disable --now borg-backup.timer 2>/dev/null || true
fi
