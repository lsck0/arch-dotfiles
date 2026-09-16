#!/usr/bin/env bash
# Interactive system update, launched from the bar's update indicator
# (plugins/bar/widgets/SystemUpdate.qml) and usable on its own from a terminal.
#
# WHY THIS FILE EXISTS. SystemUpdate.qml's click action ran
# `ghostty -e /usr/local/bin/system-update.sh` — a path nothing in this repo
# has ever created, and which link.sh could not create either (it only links
# into ~/.local/bin). The indicator appeared when updates were pending and then
# did nothing at all when clicked, with the failure landing in a detached
# terminal that closed immediately. Living here means link.sh links it to
# ~/.local/bin/system-update like every other shell helper, so a fresh install
# reproduces it.
#
# yay, not pacman: the widget's own check uses `checkupdates`, which only sees
# the official repos, but this box installs from the AUR too (see install.sh)
# and updating only half of it is how partial-upgrade breakage starts.
#
# Never --noconfirm. This is the interactive path on purpose — the caller opens
# a real terminal for it precisely so the transaction can be read before it is
# accepted.
set -uo pipefail

if ! command -v yay >/dev/null 2>&1; then
    echo "yay is not installed — see install.sh" >&2
    exit 1
fi

echo "==> Repo + AUR packages"
yay -Syu
status=$?

# Orphans accumulate quietly and are only ever noticed as disk usage. Listing
# them is safe; removing them is the user's call, so this only reports.
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

# The caller is a terminal opened purely for this, so it would vanish with the
# result still on screen for a fraction of a second.
echo
read -r -n 1 -p "Press any key to close… "
echo
exit "$status"
