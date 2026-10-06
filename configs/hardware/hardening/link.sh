#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# wsl runs microsoft's kernel, these host-hardening keys do not exist there; config.sh exports FORM_FACTOR, standalone reads platform_load's copy
form_factor="${FORM_FACTOR:-$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/form-factor" 2>/dev/null)}"
[[ "$form_factor" == wsl ]] && exit 0

set -e

sudo install -Dm644 sysctl-hardening.conf /etc/sysctl.d/99-hardening.conf
# systemd-sysctl, not sysctl -p: only it expands the conf.* globs
sudo /usr/lib/systemd/systemd-sysctl /etc/sysctl.d/99-hardening.conf
