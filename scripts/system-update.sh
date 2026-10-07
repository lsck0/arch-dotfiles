#!/usr/bin/env bash
# Update all the things: install.sh onto the latest lsck0 snapshot, config.sh, then toolchains and editor plugins.

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
[[ -z ${DIRENV_DIR-} ]] || { echo "run outside a direnv directory" >&2; exit 1; }

echo "ARE U SURE?"
read -rp "Type 'y' to continue: " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborting update."
    exit 1
fi

run_if_present() {
    local bin=$1
    shift
    if command -v "$bin" >/dev/null 2>&1; then
        "$bin" "$@"
    fi
}

# timeshift-autosnap snapshots before install.sh's transaction; it exits 1 for logged failures, 2 for an abort that stops here
./install.sh || (($? == 1))
./config.sh || echo "system-update: config.sh finished with failures, see FAILURES.config" >&2
run_if_present flatpak update --assumeyes

# language toolchains

run_if_present rustup update

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

# userland; protonup and the tmux plugins come from config.sh, the latter pinned

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprpm >/dev/null 2>&1; then
    # not `yes |`: pipefail would fail on yes dying of sigpipe
    hyprpm update -f < <(yes)
fi

run_if_present tldr --update_cache

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
