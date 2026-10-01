#!/usr/bin/env bash

if ! command -v rtk >/dev/null 2>&1; then
    exit 0
fi

set -e

# unattended, the patch prompts default to no and hooks never register
rtk init -g --auto-patch --agent hermes
rtk init -g --auto-patch --agent claude
rtk init -g --auto-patch --copilot
rtk init -g --auto-patch --gemini
