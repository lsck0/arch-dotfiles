#!/usr/bin/env bash

unit_install timezone-auto.service timezone-auto.timer
systemctl --user enable --now timezone-auto.timer

# offline is fine here, the next network change retries
./timezone-auto.sh check || true
