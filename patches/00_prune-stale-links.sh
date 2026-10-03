#!/usr/bin/env bash
# Drop command symlinks that point at scripts the repo no longer has.
#
# scripts/link.sh and the configs/*/link.sh scripts only ever `ln -sfn`. A renamed or deleted script therefore
# leaves its old name in /usr/local/bin or ~/.local/bin forever, shadowing a real binary of the same name and
# surviving every config.sh run. Nothing short of a reinstall cleaned that up before patches existed.

set -uo pipefail

prune() { # dir, sudo?
    local dir="$1" use_sudo="$2" link
    [[ -d "$dir" ]] || return 0
    # -xtype l: a symlink whose target does not resolve. Plain files and live links are never touched.
    while IFS= read -r -d '' link; do
        # only ours: a broken link into some other prefix is not this repo's to remove
        case "$(readlink "$link")" in
            */arch-dotfiles/*) ;;
            *) continue ;;
        esac
        echo "patch: removing dangling $link -> $(readlink "$link")"
        if [[ "$use_sudo" == sudo ]]; then sudo rm -f "$link"; else rm -f "$link"; fi
    done < <(find "$dir" -maxdepth 1 -xtype l -print0 2>/dev/null)
}

prune /usr/local/bin sudo
prune "$HOME/.local/bin" ""
