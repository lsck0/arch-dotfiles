#!/usr/bin/env bash
# VeraCrypt "vault in home" helper: create/mount/dismount an encrypted container.
# The password is YOUR secret: veracrypt --text prompts for it, this never stores it.
set -euo pipefail

CONTAINER="$HOME/Vault.hc"
MOUNTPOINT="$HOME/Vault"
DEFAULT_SIZE="2G"

usage() {
    echo "usage: veracrypt-vault {create [size]|mount|umount|dismount|status}" >&2
    echo "  create [size]  create $CONTAINER (default $DEFAULT_SIZE), prompts for password" >&2
    echo "  mount          mount $CONTAINER at $MOUNTPOINT, prompts for password" >&2
    echo "  umount         dismount $MOUNTPOINT (alias: dismount)" >&2
    echo "  status         list mounted VeraCrypt volumes" >&2
    exit 2
}

cmd_create() {
    # Never overwrite an existing vault: that would destroy its data.
    if [ -e "$CONTAINER" ]; then
        echo "refusing to create: $CONTAINER already exists" >&2
        exit 1
    fi
    local size="${1:-${VAULT_SIZE:-$DEFAULT_SIZE}}"
    veracrypt --text --create "$CONTAINER" \
        --size="$size" \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=ext4 \
        --volume-type=normal \
        --pim=0 \
        --keyfiles="" \
        --random-source=/dev/urandom
    echo "created $CONTAINER ($size); mount it with: veracrypt-vault mount" >&2
}

cmd_mount() {
    mkdir -p "$MOUNTPOINT"
    veracrypt --text --mount "$CONTAINER" "$MOUNTPOINT" \
        --pim=0 --keyfiles="" --protect-hidden=no
    echo "mounted at $MOUNTPOINT" >&2
}

cmd_dismount() {
    veracrypt --text --dismount "$MOUNTPOINT"
    echo "dismounted $MOUNTPOINT" >&2
}

cmd_status() {
    veracrypt --text --list
}

[ $# -ge 1 ] || usage
sub="$1"; shift || true
case "$sub" in
    create) cmd_create "$@" ;;
    mount) cmd_mount ;;
    umount|dismount) cmd_dismount ;;
    status) cmd_status ;;
    *) usage ;;
esac
