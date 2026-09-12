#!/usr/bin/env bash

if ! command -v rtk >/dev/null 2>&1; then
    exit 0
fi

set -ex

rtk init -g --agent hermes
rtk init -g --agent claude
rtk init -g --copilot
rtk init -g --gemini
