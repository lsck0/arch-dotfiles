#!/usr/bin/env bash
# Every scripts/*.sh and *.py as a command in ~/.local/bin; user scripts stay out of root's secure_path.

shopt -s nullglob
commands=()
for script in *.sh *.py; do
    [[ "$script" == link.sh ]] || commands+=("$script")
done
link_commands "${commands[@]}"
