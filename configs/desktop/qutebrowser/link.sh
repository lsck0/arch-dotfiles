#!/usr/bin/env bash

link_into "${HOME}/.config/qutebrowser" config.py
# a per-user copy: the page needs absolute paths into this home (firefox resolves relative ones against the repo);
# toggle-font edits the repo copy, the next config run carries it over
file_render startpage.html "${HOME}/.config/qutebrowser/startpage.html" HOME="$HOME" DOTFILES="$DOTFILES"
