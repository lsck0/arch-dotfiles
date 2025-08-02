#!/bin/env bash

set -ex

rm -rf ~/.config/emacs
git clone --depth 1 https://github.com/doomemacs/doomemacs ~/.config/emacs
~/.config/emacs/bin/doom install --aot --force
