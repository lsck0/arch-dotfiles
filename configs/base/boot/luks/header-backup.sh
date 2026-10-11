#!/usr/bin/env bash
# the root volume's LUKS header into the git-crypt secrets, never onto a plaintext disk: a damaged header loses the whole
# disk. run as the admin after every keyslot change (passphrase, yubikey, TPM seal), then commit secrets. a backup keeps
# opening with whatever passphrase it held, so after removing a leaked one, overwrite every older copy
set -euo pipefail

: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
source "$DOTFILES/scripts/lib/secrets.sh"
SECRETS="$DOTFILES/secrets"
STAGE_KEY_FILE=/etc/cryptsetup-keys.d/root.key

die() { echo "header-backup: $*" >&2; exit 1; }

secret_require_unlocked "$DOTFILES"
root_src=$(findmnt -n -o SOURCE /)
root_src=${root_src%%[*}
[[ "$root_src" == /dev/mapper/* ]] || die "/ is not on a LUKS mapping"
part=$(lsblk -lnso NAME,TYPE "$root_src" | awk '$2 == "part" {print $1; exit}')
[[ -n "$part" ]] || die "no partition under $root_src"

dest="$SECRETS/luks-header-$(</etc/hostname).img"
# git-crypt encrypts only what .gitattributes filters, a plaintext header must never reach the pushed repo
[[ "$(git -C "$SECRETS" check-attr filter -- "${dest##*/}")" == *": filter: git-crypt" ]] \
    || die "secrets/.gitattributes does not git-crypt ${dest##*/}"
# the stage keyfile's slot would ride along, and that key may still sit in freed ESP blocks: only once stage.sh dropped it
! sudo test -e "$STAGE_KEY_FILE" || die "the stage keyfile is still armed, run this after the stage chain"

# root-only tmpfs: cryptsetup writes the backup as root and refuses an existing file
tmp=$(sudo mktemp -d)
trap 'sudo rm -rf "$tmp"' EXIT
sudo cryptsetup luksHeaderBackup "/dev/$part" --header-backup-file "$tmp/header.img"
sudo cat "$tmp/header.img" | install -m600 /dev/stdin "$dest"
cryptsetup luksDump "$dest" >/dev/null || die "$dest is no LUKS header"
echo "header-backup: /dev/$part -> $dest, commit secrets to keep it off this disk"
