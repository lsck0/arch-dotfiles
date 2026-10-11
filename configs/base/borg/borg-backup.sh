#!/usr/bin/env bash
# Daily borg backup of $HOME to the homelab NAS. Repo key is encrypted by a passphrase kept in the git-crypt
# secrets worktree (secrets/borg-passphrase). Skips cleanly when the NAS isn't mounted or secrets are locked,
# so a laptop off the homelab or a locked vault never errors the timer.
set -euo pipefail
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"

NAS=/mnt/homelab
export BORG_REPO="$NAS/backups/borg/$(hostname)"
PASSFILE="${DOTFILES_SECRETS:-$DOTFILES/secrets}/borg-passphrase"

mountpoint -q "$NAS" || { echo "borg: $NAS not mounted, skipping" >&2; exit 0; }
[[ -r "$PASSFILE" ]] || { echo "borg: no passphrase at $PASSFILE (add secrets/borg-passphrase), skipping" >&2; exit 0; }
# a locked git-crypt blob starts with the bytes "\0GITCRYPT"; don't feed that as a passphrase
[[ "$(head -c 8 "$PASSFILE" | tr -d '\0')" != GITCRYPT ]] || { echo "borg: secrets locked, skipping" >&2; exit 0; }

export BORG_PASSCOMMAND="cat $PASSFILE"
export BORG_RELOCATED_REPO_ACCESS_IS_OK=no BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=no

# init once: repokey-blake2 stores the (passphrase-encrypted) key inside the repo, so no separate keyfile to lose
borg list >/dev/null 2>&1 || borg init --encryption=repokey-blake2

borg create --stats --compression zstd,3 --exclude-caches --one-file-system \
    --exclude-if-present .nobackup \
    --exclude "$HOME/.cache" \
    --exclude "$HOME/.local/share/Trash" \
    --exclude "$HOME/.local/share/Steam" \
    --exclude "$HOME/.local/share/containers" \
    --exclude "$HOME/.var/app/*/cache" \
    --exclude "$HOME/Downloads" \
    --exclude "$HOME/**/node_modules" \
    --exclude "$HOME/**/target" \
    --exclude "$HOME/**/.venv" \
    "::{hostname}-{now:%Y%m%d-%H%M%S}" "$HOME"

borg prune --glob-archives '{hostname}-*' --keep-daily 7 --keep-weekly 4 --keep-monthly 6
borg compact
