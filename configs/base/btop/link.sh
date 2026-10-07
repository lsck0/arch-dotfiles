#!/usr/bin/env bash

# a fresh user may have no ~/.config yet, and btop sorts first
mkdir -p "$HOME/.config"
ln -sfn "${PWD}" "$HOME/.config/btop"
