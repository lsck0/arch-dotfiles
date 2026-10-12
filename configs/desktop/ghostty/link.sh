#!/usr/bin/env bash

link_dir "${PWD}" "$HOME/.config/ghostty"
# volatile like tlp's forced mode, so a reboot never leaves power-saver tweaks behind
mkdir -p "$HOME/.cache"
ln -sfn "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/toggles/ghostty-powersave.conf" "$HOME/.cache/ghostty-powersave.conf"
# hyprland's xwayland GDK_SCALE (java_ui_scale's rule) reaches launched apps, not the shells of this resident instance;
# env only goes to the commands a tab runs, so ghostty's own gtk keeps the compositor's fractional scale
env_conf="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/ghostty-env.conf"
mkdir -p "${env_conf%/*}"
echo "env = GDK_SCALE=$(java_ui_scale)" >"$env_conf"

dropin_install app-com.mitchellh.ghostty.service systemd/override.conf || true
# a prefix drop-in, so every app-ghostty-surface-transient-<pid>.scope ghostty creates picks it up
dropin_install app-ghostty-surface-transient-.scope systemd/surface.conf || true
# not loaded yet on a first run, then there is nothing to reset
systemctl --user reset-failed app-com.mitchellh.ghostty.service 2>/dev/null || true
# prewarm at login, windows open over d-bus via ghostty +new-window
systemctl --user enable app-com.mitchellh.ghostty.service
