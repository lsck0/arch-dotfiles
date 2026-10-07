#!/usr/bin/env bash

# the launcher entry runs gparted through pkexec (link.sh); polkit lets an admin at the machine through unprompted
install -Dm644 49-gparted.rules /etc/polkit-1/rules.d/49-gparted.rules
