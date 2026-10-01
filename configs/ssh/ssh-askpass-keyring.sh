#!/usr/bin/env bash
# passphrase from the login keyring; a fresh install has no keyring entry yet, so fall back to the secrets copy
secret-tool lookup ssh-key ssh_privatekey 2>/dev/null && exit 0

here="$(dirname "$(readlink -f "$0")")"
source "$here/../../scripts/lib/secrets.sh"
passphrase="$here/../secrets/ssh_passphrase"
secret_is_plaintext "$passphrase" && exec head -n1 "$passphrase"
exit 1
