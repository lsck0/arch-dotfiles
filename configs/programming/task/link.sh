#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh

set -e

mkdir -p ~/.task/hooks
mkdir -p ~/.timewarrior
mkdir -p ~/.config/bugwarrior ~/.local/state/bugwarrior

ln -sfn "${PWD}/taskrc" "$HOME/.taskrc"

HOOK=/usr/share/doc/timew/ext/on-modify.timewarrior
if [[ -f "$HOOK" ]]; then
    install -m755 "$HOOK" ~/.task/hooks/on-modify.timewarrior
else
    echo "task: $HOOK not found (timew not installed), skipping hook" >&2
fi

# taskwarrior rejects bugwarrior's udas unless declared; bugwarrior itself is luca-only
if is_personal && command -v bugwarrior >/dev/null 2>&1 && [[ -e "$HOME/.config/bugwarrior/bugwarrior.toml" ]]; then
    bugwarrior uda > ~/.config/bugwarrior/uda.taskrc.tmp \
        && mv -f ~/.config/bugwarrior/uda.taskrc.tmp ~/.config/bugwarrior/uda.taskrc \
        || { rm -f ~/.config/bugwarrior/uda.taskrc.tmp; touch ~/.config/bugwarrior/uda.taskrc; }
else
    touch ~/.config/bugwarrior/uda.taskrc
fi
