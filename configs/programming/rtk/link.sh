#!/usr/bin/env bash

# unattended, the patch prompts default to no and hooks never register
rtk init -g --auto-patch --agent hermes
rtk init -g --auto-patch --agent claude
rtk init -g --auto-patch --copilot
rtk init -g --auto-patch --gemini
