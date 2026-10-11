#!/usr/bin/env bash
# Bruno GUI preferences: match the editor font, follow the system theme, and turn anonymous telemetry off.
# json_update merges, so anything you change later in the app survives; only codeFont and telemetry are forced.

conf="${XDG_CONFIG_HOME:-$HOME/.config}/bruno/preferences.json"
json_update "$conf" '
    .version = (.version // "1")
    | .preferences.theme = (.preferences.theme // "system")
    | .preferences.font.codeFont = "Kode Mono"
    | .preferences.telemetry = false
'
