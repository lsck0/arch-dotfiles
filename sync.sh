#!/usr/bin/env bash
# Back up live app state into the repo, then commit configs/secrets and the whole tree as the next signed "Generation: N" and push.

set -e
cd "$(dirname "$(readlink -f "$0")")"

source ./scripts/lib/secrets.sh

LAST_GEN=$(git log --format=%s | grep -m1 -oE '^Generation: [0-9]+' | grep -oE '[0-9]+' || echo 0)
COMMIT_MSG="Generation: $((LAST_GEN + 1))"

die() { echo "sync: $*" >&2; exit 1; }

# a failed backup only warns, the rest of the tree still gets committed
backup() { "$@" || echo "sync: $1 failed, its state is not backed up" >&2; }

# readme_pin_bootstrap: rewrite README.md's pinned sha256 to the bootstrap.sh being committed
readme_pin_bootstrap() {
    local sha256
    sha256=$(sha256sum bootstrap.sh | cut -d' ' -f1)
    grep -qE '[0-9a-f]{64}  bootstrap\.sh' README.md || die "README.md has no '<sha256>  bootstrap.sh' pin to update"
    sed -i -E "s/[0-9a-f]{64}  bootstrap\.sh/$sha256  bootstrap.sh/g" README.md
}

## PREFLIGHT

# the key bootstrap.sh trusts, so every pushed generation is one a fresh install accepts
SIGNING_KEY_FINGERPRINT=$(sed -n 's/^SIGNING_KEY_FINGERPRINT=\([0-9A-F]\{40\}\)$/\1/p' bootstrap.sh)
[[ "$SIGNING_KEY_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]] || die "bootstrap.sh has no single SIGNING_KEY_FINGERPRINT=<40 hex>"
# an unsigned push would make the next bootstrap refuse master, so stop here instead
gpg --batch --list-secret-keys "$SIGNING_KEY_FINGERPRINT" >/dev/null 2>&1 \
    || die "no secret key $SIGNING_KEY_FINGERPRINT to sign with, import it: ./scripts/yubikey.sh unlock && ./configs/gnupg/link.sh"
readme_pin_bootstrap

## BACKUP

# link.sh scripts restore all of these on the next config.sh run
backup ./scripts/backup-kde.sh
# these write into configs/secrets, which must be unlocked or plaintext would land in a GITCRYPT worktree
if secret_is_plaintext configs/secrets/pgp_privatekey.asc; then
    backup ./scripts/backup-obs.sh
    backup ./scripts/backup-claude.sh
    backup ./scripts/backup-gh.sh
    backup ./scripts/backup-dalamud.sh
    backup ./scripts/backup-ffxiv.sh

    # secrets first, so the generation commit below records its new revision
    if [ -n "$(git -C configs/secrets status --porcelain)" ]; then
        git -C configs/secrets add -A
        git -C configs/secrets commit -m "chore(sync): back up live app state"
    fi
    # submodule update leaves a detached HEAD, so push it to the branch explicitly
    git -C configs/secrets push origin HEAD:master
else
    echo "sync: configs/secrets is locked, skipping the obs, claude, gh, dalamud and ffxiv backups" >&2
fi

## COMMIT

git add .
# bootstrap.sh and the lsck0 builder consume master directly, so a script that does not parse or an untagged list entry never becomes a Generation
git ls-files -z '*.sh' | xargs -0 -n1 bash -n || die "a staged script does not parse, nothing committed"
awk '/^[A-Z_]+=\($/ { f = 1; next } f && /^\)/ { f = 0 } f && NF && !/# \[[a-z]+\]/ { print "install.sh:" FNR ": no [group] tag: " $0; bad = 1 } END { exit bad }' install.sh \
    || die "install.sh has list entries without a [group] tag, nothing committed"
git -c gpg.format=openpgp commit -S"$SIGNING_KEY_FINGERPRINT" -m "${COMMIT_MSG}"
git push
