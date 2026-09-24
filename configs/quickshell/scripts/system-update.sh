#!/usr/bin/env bash
# Interactive system update, launched from the bar's update indicator (plugins/bar/widgets/SystemUpdate.qml) and usable on its own from a terminal.
set -uo pipefail

if ! command -v yay >/dev/null 2>&1; then
    echo "yay is not installed — see install.sh" >&2
    exit 1
fi

echo "==> Repo + AUR packages"
yay -Syu
status=$?

# Orphans accumulate quietly and are only ever noticed as disk usage.
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

# The caller is a terminal opened purely for this, so it would vanish with the result still on screen for a fraction of a second.
echo
read -r -n 1 -p "Press any key to close… "
echo
exit "$status"
