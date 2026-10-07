#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# passphrase from the login keyring, else the secrets copy on a fresh install
set -euo pipefail
secret-tool lookup ssh-key ssh_privatekey 2>/dev/null && exit 0

source "$DOTFILES/scripts/lib/secrets.sh"
passphrase="$DOTFILES/secrets/ssh_passphrase"
secret_is_plaintext "$passphrase" && exec head -n1 "$passphrase"
exit 1
