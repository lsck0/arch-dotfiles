#!/usr/bin/env bash
# Update all the things

set -x

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/system-update"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/system-update-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG_FILE") 2>&1
echo "Logging to $LOG_FILE"

echo "ARE U SURE?"
read -p "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

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

sudo pacman-key --init
sudo pacman-key --populate archlinux
# sudo pacman-key --refresh-keys

yay -Syyu --rebuildall --answerclean A --answerdiff N --noconfirm
flatpak update --assumeyes
nix-channel --update

# language toolchains

mise upgrade

rustup update
cargo install-update -a --locked

opam update
opam upgrade

ghcup upgrade
ghcup install cabal latest
ghcup install ghc latest
ghcup install hls latest
ghcup install stack latest

# userland

yes | hyprpm update -f

protonup -y

tldr --update_cache

~/.tmux/plugins/tpm/bin/update_plugins all

nvim --headless "+Lazy! sync" +MasonUpdate +TSUpdate +qa
