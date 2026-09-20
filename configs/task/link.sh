#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v task >/dev/null 2>&1; then
    exit 0
fi

set -ex

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

# bugwarrior stores its issue metadata in taskwarrior UDAs, which taskwarrior
# only accepts if they are declared. `bugwarrior uda` prints those declarations
# for the configured targets; ~/.taskrc includes the result. The file is
# created empty when bugwarrior is missing, because an include that does not
# resolve is a hard error for every `task` invocation.
if command -v bugwarrior >/dev/null 2>&1 && [[ -e "$HOME/.config/bugwarrior/bugwarrior.toml" ]]; then
    bugwarrior uda > ~/.config/bugwarrior/uda.taskrc.tmp \
        && mv -f ~/.config/bugwarrior/uda.taskrc.tmp ~/.config/bugwarrior/uda.taskrc \
        || { rm -f ~/.config/bugwarrior/uda.taskrc.tmp; touch ~/.config/bugwarrior/uda.taskrc; }
else
    touch ~/.config/bugwarrior/uda.taskrc
fi
