#!/usr/bin/env bash

# /model in a session overwrites this key
json_update "${HOME}/.copilot/settings.json" '.model = "claude-sonnet-5"'
# no telemetry key: copilot cli has no local opt-out (`copilot help config`), only the account's
# github.com/settings/copilot data-use toggles; gh's own is GH_TELEMETRY in configs/core/zsh/no-telemetry.conf
