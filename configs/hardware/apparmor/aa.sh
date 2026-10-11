#!/usr/bin/env bash
# Manually decide which apps AppArmor confines, and how. The dotfiles ship a baseline (profiles.conf ->
# /etc/apparmor/{include.d,flags.d}/dotfiles.conf); this tool layers YOUR choices into a separate
# `manual.conf` in the same drop-in dirs, which config runs never touch, then rebuilds with apparmor.d's
# aa-install (the same path the module and the pacman hook use), so choices persist across both.
#
#   aa                      show loaded profiles and their modes, plus your manual choices
#   aa list [filter]        list available apparmor.d profile names (optionally grep-filtered)
#   aa enforce <profile>    confine <profile> and block violations
#   aa complain <profile>   confine <profile> but only log violations (safe to try)
#   aa off <profile>        stop confining <profile>
#
# <profile> is an apparmor.d profile name, e.g. firefox, discord, signal-desktop, thunderbird (see `aa list`).
set -euo pipefail

INC=/etc/apparmor/include.d/manual.conf
FLAGS=/etc/apparmor/flags.d/manual.conf
ETC_PROFILES=/etc/apparmor.d
SRC_PROFILES=/usr/share/apparmor.d

die() { echo "aa: $*" >&2; exit 1; }
command -v aa-install >/dev/null 2>&1 || die "apparmor.d (aa-install) is not installed"

# every profile apparmor.d can build, by basename
available() {
    { [ -d "$SRC_PROFILES" ] && find "$SRC_PROFILES" -type f -not -path '*/abstractions/*' \
          -not -path '*/tunables/*' -printf '%f\n'
      [ -d "$ETC_PROFILES" ] && find "$ETC_PROFILES" -maxdepth 1 -type f -printf '%f\n'
    } 2>/dev/null | sort -u
}

known() { available | grep -qxF "$1"; }

apply() { sudo aa-install --install; }

set_mode() {
    local p="$1" mode="$2"
    known "$p" || die "no apparmor.d profile named '$p' (try: aa list ${p})"
    sudo touch "$INC" "$FLAGS"
    grep -qxF "$p" "$INC" 2>/dev/null || echo "$p" | sudo tee -a "$INC" >/dev/null
    sudo sed -i "\|^${p}[[:space:]]|d" "$FLAGS"
    echo "$p $mode" | sudo tee -a "$FLAGS" >/dev/null
    apply
    echo "aa: $p -> $mode (reboot-safe)"
}

off() {
    local p="$1"
    sudo touch "$INC" "$FLAGS"
    sudo sed -i "\|^${p}\$|d" "$INC"
    sudo sed -i "\|^${p}[[:space:]]|d" "$FLAGS"
    sudo aa-disable "$ETC_PROFILES/$p" 2>/dev/null || true
    apply
    echo "aa: $p is no longer confined"
}

case "${1:-status}" in
    status|"")
        echo "# loaded profiles and modes"; sudo aa-status --profiles 2>/dev/null || sudo aa-status
        echo; echo "# your manual choices ($FLAGS)"; sudo cat "$FLAGS" 2>/dev/null || echo "  (none yet)"
        ;;
    list)     available | { [ $# -ge 2 ] && grep -i "$2" || cat; } ;;
    enforce)  [ $# -ge 2 ] || die "usage: aa enforce <profile>"; set_mode "$2" enforce ;;
    complain) [ $# -ge 2 ] || die "usage: aa complain <profile>"; set_mode "$2" complain ;;
    off|disable) [ $# -ge 2 ] || die "usage: aa off <profile>"; off "$2" ;;
    *) die "usage: aa [status|list [filter]|enforce <profile>|complain <profile>|off <profile>]" ;;
esac
