#!/usr/bin/env bash
# Gemini CLI phones home usage stats by default; turn it off (matches the opt-outs for bruno/zed/vscode/copilot).
json_update "${HOME}/.gemini/settings.json" '.usageStatisticsEnabled = false | .telemetry.enabled = false'
