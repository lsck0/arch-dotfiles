#!/usr/bin/env bash

# ly's pam stack already starts and unlocks the keyring
for unit in gnome-keyring-daemon.service gnome-keyring-daemon.socket; do
    if unit_present "$unit"; then systemctl --user mask "$unit"; fi
done
for unit in pipewire-pulse.service pipewire-pulse.socket ssh-agent.service; do
    if unit_present "$unit"; then systemctl --user enable "$unit"; fi
done
