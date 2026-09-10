#!/usr/bin/env bash
# JSON snapshot of sinks/sources for AudioIO.qml's device picker.
set -euo pipefail

default_sink=$(pactl get-default-sink)
default_source=$(pactl get-default-source)

sinks=$(pactl -f json list sinks | jq -c '[.[] | {name: .name, description: .description}]')
sources=$(pactl -f json list sources | jq -c '[.[] | select(.name | test("\\.monitor$") | not) | {name: .name, description: .description}]')

jq -nc --argjson sinks "$sinks" --argjson sources "$sources" \
  --arg defaultSink "$default_sink" --arg defaultSource "$default_source" \
  '{sinks: $sinks, sources: $sources, defaultSink: $defaultSink, defaultSource: $defaultSource}'
