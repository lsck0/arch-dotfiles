#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/quickshell ${HOME}/.local/bin
ln -sf ${PWD}/shell.qml ${HOME}/.config/quickshell/shell.qml
# Live-watched theme knobs (font + palette conditioning). Tracked config the
# user edits, unlike shell.json which is runtime state under XDG_STATE_HOME.
ln -sf ${PWD}/theme.json ${HOME}/.config/quickshell/theme.json
ln -sf ${PWD}/Commons ${HOME}/.config/quickshell/Commons
ln -sf ${PWD}/Ui ${HOME}/.config/quickshell/Ui
ln -sf ${PWD}/plugins ${HOME}/.config/quickshell/plugins
ln -sf ${PWD}/services ${HOME}/.config/quickshell/services
ln -sf ${PWD}/scripts ${HOME}/.config/quickshell/scripts
# Quickshell plugins invoke these by basename; link them without exposing
# Quickshell-only helpers through the global scripts linker.
for script in "${PWD}"/scripts/*.sh; do
    ln -sf "$script" "${HOME}/.local/bin/$(basename "$script" .sh)"
done
# reminder.sh lives in the top-level scripts/ dir (also linked into
# /usr/local/bin/reminder by scripts/link.sh, for ReminderFlow.qml's
# launcher flow), not here — but Clock.qml's Pomodoro panel calls it via
# ~/.local/bin/reminder specifically, same as every other quickshell-owned
# helper, so it needs its own link rather than relying on PATH resolution.
ln -sf "${PWD}/../../scripts/reminder.sh" "${HOME}/.local/bin/reminder"
