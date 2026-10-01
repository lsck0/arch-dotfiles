#!/usr/bin/env bash

if ! command -v rtk >/dev/null 2>&1; then
    exit 0
fi

set -e

# --auto-patch: unattended, the settings.json patch prompts default to no and the hooks never register
rtk init -g --auto-patch --agent hermes
rtk init -g --auto-patch --agent claude
rtk init -g --auto-patch --copilot
rtk init -g --auto-patch --gemini
