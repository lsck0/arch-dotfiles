#!/usr/bin/env bash

# scripts/toggles run from the bar and the menu, with no terminal to ask in: the root half is this helper, and polkit
# lets an admin at the machine run it and start/stop the toggled units without a password or fingerprint
install -m755 toggle-root /usr/local/bin/toggle-root
install -Dm644 49-toggles.rules /etc/polkit-1/rules.d/49-toggles.rules
