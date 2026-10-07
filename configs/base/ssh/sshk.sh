#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# knock the hidden-ssh sequence (configs/hardware/nftables/fw-inbound.nft) then ssh to the real sshd on 2222: the port is filtered to scans, the knock opens it for your IP for 1h, 22 is a tarpit
set -euo pipefail
target="${1:?usage: sshk.sh [user@]<host> [ssh args...]}"; shift
host="${target#*@}"
# knock sends each syn once, one lost packet on wifi keeps 2222 shut, so re-knock until it opens
for _ in 1 2 3 4 5; do
    knock "$host" 9003 7001 8002
    HOST="$host" timeout 2 bash -c '>/dev/tcp/"$HOST"/2222' 2>/dev/null && break
done
# the secrets key once unlocked (a locked one is a git-crypt blob), then the yubikey stub; neither leaves ssh's defaults
ids=()
key="$DOTFILES/secrets/ssh_privatekey.asc"
[[ -r "$key" && "$(head -c 9 "$key" | tr -d '\0')" != GITCRYPT ]] && ids+=(-i "$key")
[[ -f "$HOME/.ssh/id_ed25519_sk" ]] && ids+=(-i "$HOME/.ssh/id_ed25519_sk")
((${#ids[@]})) && ids+=(-o IdentitiesOnly=yes)
exec ssh -p 2222 "${ids[@]}" "$target" "$@"
