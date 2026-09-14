#!/usr/bin/env bash
# Update all the things.
#
# Every external tool here comes from an install.sh PACKAGE GROUP the user
# can opt out of (interactive prompt at first install.sh run — any of the 11
# groups, including "programming", "gaming", even "base", can be deselected), so a
# tool being absent on this particular machine is an expected, normal case,
# not a bug. Before this guard existed, an opted-out toolchain just spammed
# "command not found" to stderr and moved on — harmless but noisy, and it
# masked genuine failures in the same wall of red text. Every step below is
# now `command -v`-gated with an explicit skip notice instead.

set -x

echo "ARE U SURE?"
read -p "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

# Pre-update snapshot: only if timeshift has actually been configured past
# its first-run wizard (config/boot/timeshift/link.sh writes
# /etc/timeshift/timeshift.json — see BOOT.md; on this machine btrfs-mode is
# not yet reachable since root is still a top-level subvol, so this
# correctly no-ops here until that migration happens). Guarding on the real
# config file, not just `command -v timeshift`, avoids dropping the tool
# into its interactive first-run wizard from an unattended update script.
if command -v timeshift >/dev/null 2>&1 && [ -f /etc/timeshift/timeshift.json ] \
    && ! grep -q '"do_first_run" : "true"' /etc/timeshift/timeshift.json 2>/dev/null; then
    sudo timeshift --create --comments "pre-update ($(date -Iseconds))" --tags D
else
    echo "[skip] timeshift not configured past first-run (see BOOT.md) — no pre-update snapshot" >&2
fi

# Runs a command only if its first word resolves on PATH; otherwise prints a
# one-line skip notice instead of letting the shell's own "command not
# found" (or a deeper failure inside a present-but-broken toolchain wrapper)
# stand in as the only explanation.
run_if_present() {
    local bin=$1
    shift
    if command -v "$bin" >/dev/null 2>&1; then
        "$bin" "$@"
    else
        echo "[skip] $bin not installed" >&2
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
    else
        echo "[skip] cargo-update (cargo install-update subcommand) not installed" >&2
    fi
else
    echo "[skip] rustup not installed (also skipping cargo install-update)" >&2
fi

run_if_present gup update

run_if_present npm update -g

if command -v opam >/dev/null 2>&1; then
    opam update
    opam upgrade -y
else
    echo "[skip] opam not installed" >&2
fi

if command -v ghcup >/dev/null 2>&1; then
    ghcup upgrade
    ghcup install cabal latest
    ghcup install ghc latest
    ghcup install hls latest
    ghcup install stack latest
else
    echo "[skip] ghcup not installed" >&2
fi

if command -v emacs >/dev/null 2>&1; then
    emacs --batch --eval "(progn (require 'package)
      (setq package-archives '((\"gnu\" . \"https://elpa.gnu.org/packages/\")
                                (\"nongnu\" . \"https://elpa.nongnu.org/nongnu/\")
                                (\"melpa\" . \"https://melpa.org/packages/\")))
      (package-initialize)
      (package-refresh-contents)
      (package-upgrade-all))"
else
    echo "[skip] emacs not installed" >&2
fi

# userland

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprpm >/dev/null 2>&1; then
    yes | hyprpm update -f
fi

protonup_link="$(dirname "$(readlink -f "$0")")/../configs/protonup/link.sh"
if [ -d "$HOME/.steam" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    "$protonup_link"
else
    echo "[skip] protonup/link.sh (no ~/.steam, or curl/jq missing)" >&2
fi

run_if_present tldr --update_cache

tpm_update="$HOME/.tmux/plugins/tpm/bin/update_plugins"
if [ -x "$tpm_update" ]; then
    "$tpm_update" all
else
    echo "[skip] tmux plugin manager not installed at $tpm_update" >&2
fi

if command -v nvim >/dev/null 2>&1; then
    nvim --headless "+Lazy! sync" +MasonUpdate +MasonToolsUpdateSync \
        "+MasonInstall glsl_analyzer" \
        "+lua require('nvim-treesitter').update():wait(600000)" +qa
else
    echo "[skip] nvim not installed" >&2
fi
