#!/usr/bin/env bash

# capture without root for every admin; a later admin joins on the next config run
if command -v wireshark >/dev/null 2>&1; then
    group_add_admins wireshark
fi
