#!/usr/bin/env bash
# Knock the hidden-ssh sequence (configs/nftables/fw-inbound.nft), then ssh to the real sshd on 2222.
# The real port is filtered to scans; the knock opens it for your IP for 1h. 22 is a tarpit.
set -euo pipefail
target="${1:?usage: sshk.sh [user@]<host> [ssh args...]}"; shift
host="${target#*@}"
# knock sends each syn once, one lost packet on wifi keeps 2222 shut, so re-knock until it opens
for _ in 1 2 3 4 5; do
    knock "$host" 7001 8002 9003
    HOST="$host" timeout 2 bash -c '>/dev/tcp/"$HOST"/2222' 2>/dev/null && break
done
exec ssh -p 2222 -i ~/projects/arch-dotfiles/configs/secrets/ssh_privatekey.asc -o IdentitiesOnly=yes "$target" "$@"
