#!/usr/bin/env bash
# drop zinit (generation 487: zshrc sources oh-my-zsh and the zsh plugins from packages) and the completion dump that still lists its fpath

set -euo pipefail

rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/zinit" "${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh/completions"
rm -f "$HOME/.zcompdump" "$HOME/.zcompdump.zwc"
