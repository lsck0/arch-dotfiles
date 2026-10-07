#!/usr/bin/env bash

# /model in a session overwrites this key
json_update "${HOME}/.copilot/settings.json" '.model = "claude-sonnet-5"'
