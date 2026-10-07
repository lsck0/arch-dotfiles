#!/usr/bin/env bash

# daily trash cleanup, home trash and the tmpfs trash
unit_install trash-empty.service trash-empty.timer
systemctl --user enable --now trash-empty.timer
