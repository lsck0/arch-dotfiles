#!/usr/bin/env bash

# windows owns kernel, boot, drivers, power, audio and network under wsl; nothing here applies
[[ "$FORM_FACTOR" != wsl ]] || exit 0

# lactd idles on its socket and changes nothing until a setting is applied in the gui
systemctl enable --now lactd.service
