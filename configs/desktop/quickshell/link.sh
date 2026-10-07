#!/usr/bin/env bash

# a real dir left by quickshell itself is moved aside, not deleted
link_dir "${PWD}" "${HOME}/.config/quickshell"
link_commands scripts/*.sh
