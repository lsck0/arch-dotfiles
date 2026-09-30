#!/usr/bin/env bash
set -uo pipefail

if ! command -v yay >/dev/null 2>&1; then
    echo "yay is not installed, see install.sh" >&2
    exit 1
fi

echo "==> Repo + AUR packages"
yay -Syu
status=$?

orphans=$(pacman -Qtdq 2>/dev/null || true)
if [[ -n "$orphans" ]]; then
    echo
    echo "==> Orphaned packages (remove with: sudo pacman -Rns \$(pacman -Qtdq))"
    printf '%s\n' "$orphans"
fi

echo
if ((status == 0)); then
    echo "Update finished."
else
    echo "Update exited with status $status." >&2
fi

# the terminal was opened just for this, keep it up
echo
read -r -n 1 -p "Press any key to close... "
echo
exit "$status"
