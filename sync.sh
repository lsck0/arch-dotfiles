#!/usr/bin/env bash
# Back up live app state into the repo, then commit configs/secrets and the whole tree as the next "Generation: N" and push.

set -e
cd "$(dirname "$(readlink -f "$0")")"

source ./scripts/lib/secrets.sh

LAST_GEN=$(git log --format=%s | grep -m1 -oE '^Generation: [0-9]+' | grep -oE '[0-9]+' || echo 0)
COMMIT_MSG="Generation: $((LAST_GEN + 1))"

# a failed backup only warns, the rest of the tree still gets committed
backup() { "$@" || echo "sync: $1 failed, its state is not backed up" >&2; }

## BACKUP

# link.sh scripts restore all of these on the next config.sh run
backup ./scripts/backup-kde.sh
# these write into configs/secrets, which must be unlocked or plaintext would land in a GITCRYPT worktree
if secret_is_plaintext configs/secrets/pgp_privatekey.asc; then
    backup ./scripts/backup-obs.sh
    backup ./scripts/backup-claude.sh
    backup ./scripts/backup-gh.sh
    backup ./scripts/backup-dalamud.sh

    # secrets first, so the generation commit below records its new revision
    if [ -n "$(git -C configs/secrets status --porcelain)" ]; then
        git -C configs/secrets add -A
        git -C configs/secrets commit -m "chore(sync): back up live app state"
    fi
    # submodule update leaves a detached HEAD, so push it to the branch explicitly
    git -C configs/secrets push origin HEAD:master
else
    echo "sync: configs/secrets is locked, skipping the obs, claude, gh and dalamud backups" >&2
fi

## COMMIT

git add .
git commit -m "${COMMIT_MSG}"
git push
