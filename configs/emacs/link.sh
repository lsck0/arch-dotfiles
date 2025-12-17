#!/usr/bin/env bash

set -ex

rm -rf ~/.config/emacs
git clone https://github.com/doomemacs/doomemacs ~/.config/emacs --depth 1
~/.config/emacs/bin/doom install --aot --force
