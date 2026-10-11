#!/usr/bin/env bash

link_dir "${PWD}" "$HOME/.config/emacs"

# the fallback editor has to work offline on its first start: install its packages now (use-package-always-ensure)
# instead of on first launch; the stamp only after a full load, so a run that was offline tries again
STAMP="${PWD}/elpa/.dotfiles-prefetched"
if command -v emacs >/dev/null 2>&1 && [[ ! -e "$STAMP" ]]; then
    if emacs --batch --init-directory "$HOME/.config/emacs" \
        -l "$HOME/.config/emacs/early-init.el" -l "$HOME/.config/emacs/init.el" >/dev/null 2>"${PWD}/elpa-prefetch.log"; then
        touch "$STAMP"
    else
        echo "emacs: installing its packages failed, see ${PWD}/elpa-prefetch.log; retried on the next run" >&2
    fi
fi
