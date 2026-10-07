#!/usr/bin/env bash
# Back up live app state into the repo, then commit secrets and the whole tree as the next signed "Generation: N" and push.

set -e
cd "$(dirname "$(readlink -f "$0")")"
export DOTFILES="$PWD"

source ./scripts/lib/secrets.sh

LAST_GEN=$(git log --format=%s | grep -m1 -oE '^Generation: [0-9]+' | grep -oE '[0-9]+' || echo 0)
COMMIT_MSG="Generation: $((LAST_GEN + 1))"

die() { echo "sync: $*" >&2; exit 1; }

# a failed backup only warns, the rest of the tree still gets committed
backup() { "$@" || echo "sync: $1 failed, its state is not backed up" >&2; }

## PREFLIGHT

# the key bootstrap.sh trusts, so every pushed generation is one a fresh install accepts
SIGNING_KEY_FINGERPRINT=$(sed -n 's/^SIGNING_KEY_FINGERPRINT=\([0-9A-F]\{40\}\)$/\1/p' bootstrap.sh)
[[ "$SIGNING_KEY_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]] || die "bootstrap.sh has no single SIGNING_KEY_FINGERPRINT=<40 hex>"
# an unsigned push would make the next bootstrap refuse master, so stop here instead
gpg --batch --list-secret-keys "$SIGNING_KEY_FINGERPRINT" >/dev/null 2>&1 \
    || die "no secret key $SIGNING_KEY_FINGERPRINT to sign with, import it: ./scripts/lib/yubikey.sh unlock && ./config.sh --user"

## BACKUP

# link.sh scripts restore all of these on the next config.sh run
backup ./scripts/lib/backup-kde.sh
# these write into secrets, which must be unlocked or plaintext would land in a GITCRYPT worktree
if secret_is_plaintext secrets/pgp_privatekey.asc; then
    backup ./scripts/lib/backup-obs.sh
    backup ./scripts/lib/backup-claude.sh
    backup ./scripts/lib/backup-gh.sh
    backup ./scripts/lib/backup-dalamud.sh
    backup ./scripts/lib/backup-ffxiv.sh
    backup ./scripts/lib/backup-caido.sh

    # secrets first, so the generation commit below records its new revision
    if [ -n "$(git -C secrets status --porcelain)" ]; then
        git -C secrets add -A
        git -C secrets commit -m "chore(sync): back up live app state"
    fi
    # submodule update leaves a detached HEAD, so push it to the branch explicitly
    git -C secrets push origin HEAD:master
else
    echo "sync: secrets is locked, skipping the obs, claude, gh, dalamud and ffxiv backups" >&2
fi

## COMMIT

git add .
# bootstrap.sh and the lsck0 builder consume master directly, so a script that does not parse never becomes a Generation
git ls-files -z '*.sh' | xargs -0 -n1 -P"$(nproc)" bash -n || die "a staged script does not parse, nothing committed"
git -c gpg.format=openpgp commit -S"$SIGNING_KEY_FINGERPRINT" -m "${COMMIT_MSG}"
# secrets is pushed above; the main push must not recurse into submodules (qmk_firmware is read-only upstream)
git push --no-recurse-submodules
