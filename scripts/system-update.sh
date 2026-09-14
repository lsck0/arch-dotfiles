#!/usr/bin/env bash
# Update all the things.

set -x

echo "ARE U SURE?"
read -p "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

# Pre-update snapshot
if command -v timeshift >/dev/null 2>&1 && [ -f /etc/timeshift/timeshift.json ] \
    && ! grep -q '"do_first_run" : "true"' /etc/timeshift/timeshift.json 2>/dev/null; then
    sudo timeshift --create --comments "pre-update ($(date -Iseconds))" --tags D
fi

run_if_present() {
    local bin=$1
    shift
    if command -v "$bin" >/dev/null 2>&1; then
        "$bin" "$@"
    fi
}

# disable language shims
_clean_path=""
IFS=: read -ra _path_parts <<< "$PATH"
for _p in "${_path_parts[@]}"; do
    case "$_p" in
        */mise/*) ;;  # drop mise install + shim dirs
        *) _clean_path="${_clean_path:+$_clean_path:}$_p" ;;
    esac
done
export PATH="$_clean_path"
unset _clean_path _path_parts _p
unset __MISE_DIFF __MISE_WATCH __MISE_SESSION MISE_SHELL 2>/dev/null

# system packages

run_if_present pacman-key --init
run_if_present pacman-key --populate archlinux
# run_if_present pacman-key --refresh-keys

run_if_present yay -Syyu --rebuildall --answerclean A --answerdiff N --noconfirm
run_if_present flatpak update --assumeyes
run_if_present nix-channel --update

# language toolchains

run_if_present mise upgrade

if command -v rustup >/dev/null 2>&1; then
    rustup update
    if command -v cargo-install-update >/dev/null 2>&1; then
        cargo install-update -a --locked
    fi
fi

run_if_present gup update

run_if_present npm update -g

if command -v opam >/dev/null 2>&1; then
    opam update
    opam upgrade -y
fi

if command -v ghcup >/dev/null 2>&1; then
    ghcup upgrade
    ghcup install cabal latest
    ghcup install ghc latest
    ghcup install hls latest
    ghcup install stack latest
fi

# userland

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprpm >/dev/null 2>&1; then
    yes | hyprpm update -f
fi

protonup_link="$(dirname "$(readlink -f "$0")")/../configs/protonup/link.sh"
if [ -d "$HOME/.steam" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    "$protonup_link"
fi

run_if_present tldr --update_cache

tpm_update="$HOME/.tmux/plugins/tpm/bin/update_plugins"
if [ -x "$tpm_update" ]; then
    "$tpm_update" all
fi

if command -v nvim >/dev/null 2>&1; then
    nvim --headless "+Lazy! sync" +MasonUpdate +MasonToolsUpdateSync \
        "+MasonInstall glsl_analyzer" \
        "+lua require('nvim-treesitter').update():wait(600000)" +qa
fi

if command -v emacs >/dev/null 2>&1; then
    emacs --batch --eval "(progn (require 'package)
      (setq package-archives '((\"gnu\" . \"https://elpa.gnu.org/packages/\")
                                (\"nongnu\" . \"https://elpa.nongnu.org/nongnu/\")
                                (\"melpa\" . \"https://melpa.org/packages/\")))
      (package-initialize)
      (package-refresh-contents)
      (package-upgrade-all))"
fi
