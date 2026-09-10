#!/usr/bin/env bash
# Manually install or remove one or more package groups after the fact, "at
# your own risk" per the design note this implements — install.sh's own
# group filtering only ever runs once, at install time. Reads group tags
# straight out of install.sh's own PACKAGES/CARGO_PKGS/GO_PKGS array source
# (each entry is commented `# [group] description`), so it always matches
# whatever install.sh would have installed for that group.
#
# Usage: groups-apply.sh install|remove <group> [<group>...]
set -euo pipefail

INSTALL_SH="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/install.sh"
KNOWN_GROUPS="base desktop programming security creating socials gaming misc"

usage() {
    echo "Usage: $(basename "$0") install|remove <group> [<group>...]" >&2
    echo "Known groups: $KNOWN_GROUPS" >&2
    exit 1
}

[[ $# -ge 2 ]] || usage
action="$1"; shift
[[ "$action" == "install" || "$action" == "remove" ]] || usage

for g in "$@"; do
    [[ " $KNOWN_GROUPS " == *" $g "* ]] || { echo "Unknown group: $g" >&2; usage; }
done

# Pull every pacman/AUR package tagged with one of the requested groups out
# of install.sh's PACKAGES array source (comments never survive into a bash
# array at runtime, so this greps the file text itself, not the array).
# Plain substring match on "[groupname]" — deliberately not a regex (an
# unescaped literal `[` in a dynamic awk regex opens a bracket expression,
# which silently turned this into "match almost any line" the first time
# this was written; caught in testing, not left in).
pkgs=$(awk -v groups="$*" '
    BEGIN { n = split(groups, g, " ") }
    /^PACKAGES=\(/ {f=1; next}
    f && /^\)/ {f=0}
    f {
        for (i = 1; i <= n; i++) {
            if (index($0, "[" g[i] "]") > 0) {
                pkg=$1; gsub(/^[ \t]+|[ \t]+$/, "", pkg)
                if (pkg != "") print pkg
                break
            }
        }
    }
' "$INSTALL_SH")

if [[ -z "$pkgs" ]]; then
    echo "No packages tagged with group(s): $* — nothing to do." >&2
    exit 0
fi

echo "Packages in group(s) [$*]:" >&2
printf '  %s\n' $pkgs >&2
read -rp "Proceed to $action these with yay? [y/N] " confirm
[[ "$confirm" == [yY]* ]] || { echo "Aborted." >&2; exit 1; }

if [[ "$action" == "install" ]]; then
    yay -S $pkgs --noconfirm --mflags --skipinteg
else
    yay -Rns $pkgs --noconfirm
fi
