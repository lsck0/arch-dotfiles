#!/bin/bash
# Adapted from omarchy's bin/omarchy-reminder.

# omarchy:summary=Set and show lightweight desktop notification reminders
# omarchy:args=[-i|--interactive] | <minutes> [message] | show [-j|--json] | clear
# omarchy:examples=reminder.sh -i | reminder.sh 5 | reminder.sh 30 "Check the oven" | reminder.sh show | reminder.sh show --json | reminder.sh clear

set -euo pipefail

SELF_DIR="$(dirname "$(readlink -f "$0")")"
# alert.sh is a sibling here; notification-send.sh is repo-level, three up.
ALERT_BIN="$SELF_DIR/alert.sh"
BELL="󰂞"   # md-bell_ring
NOTIFY_BIN="$SELF_DIR/../../../scripts/notification-send.sh"

format_remaining() {
  local seconds=$1
  local minutes=$((seconds / 60))
  local remainder=$((seconds % 60))

  if ((minutes > 0 && remainder > 0)); then
    echo "${minutes}m ${remainder}s"
  elif ((minutes > 0)); then
    echo "${minutes}m"
  else
    echo "${remainder}s"
  fi
}

active_reminder_timers() {
  local now=${1:-$(date +%s)}
  local timer next

  while IFS=$'\t' read -r timer next; do
    [[ -z $timer || -z $next ]] && continue

    next=$((next / 1000000))
    ((next <= now)) && continue

    printf "%s\t%s\n" "$timer" "$next"
  done < <(systemctl --user list-timers --all --output=json "quickshell-reminder-*.timer" 2>/dev/null | jq -r '.[] | [.unit, .next] | @tsv')
}

open_interactive() {
  quickshell ipc -p "$HOME/.config/quickshell" call shell summon panel.reminders "{}"
}

show_reminders() {
  local timer next remaining reminder reminder_minutes body=""
  local reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-reminders"
  local reminder_message=""
  local now=$(date +%s)

  while IFS=$'\t' read -r timer next; do
    remaining=$((next - now))
    reminder=${timer%.timer}
    reminder=${reminder#quickshell-reminder-}
    reminder_minutes=${reminder%%m-*}
    reminder_message=""
    [[ -f $reminder_dir/${timer%.timer}.message ]] && reminder_message=$(<"$reminder_dir/${timer%.timer}.message")

    if [[ -n $reminder_message ]]; then
      body+="$reminder_message in $(format_remaining $remaining) ($(date -d "@$next" +%-H:%M))"$'\n'
    else
      body+="${reminder_minutes}-min reminder in $(format_remaining $remaining) ($(date -d "@$next" +%-H:%M))"$'\n'
    fi
  done < <(active_reminder_timers "$now")

  if [[ -z $body ]]; then
    "$NOTIFY_BIN" -g 󰢌 "Upcoming reminders" "No outstanding reminders"
  else
    "$NOTIFY_BIN" -g 󰢌 "Upcoming reminders" "${body%$'\n'}"
  fi
}

show_json() {
  local timer next remaining reminder reminder_minutes unit reminder_message label item_json reminders_json="[]"
  local reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-reminders"
  local now=$(date +%s)
  local count=0
  local tooltip="Set Reminder"

  while IFS=$'\t' read -r timer next; do
    count=$((count + 1))

    unit=${timer%.timer}
    reminder=${unit#quickshell-reminder-}
    reminder_minutes=${reminder%%m-*}
    [[ ! $reminder_minutes =~ ^[0-9]+$ ]] && reminder_minutes=0
    remaining=$((next - now))
    reminder_message=""
    [[ -f $reminder_dir/$unit.message ]] && reminder_message=$(<"$reminder_dir/$unit.message")

    if [[ -n $reminder_message ]]; then
      label=$reminder_message
    else
      label="${reminder_minutes}-min reminder"
    fi

    item_json=$(jq -cn \
      --arg unit "$unit" \
      --arg timer "$timer" \
      --arg label "$label" \
      --arg message "$reminder_message" \
      --arg remaining "$(format_remaining "$remaining")" \
      --arg atTime "$(date -d "@$next" +%-H:%M)" \
      --argjson minutes "$reminder_minutes" \
      --argjson at "$next" \
      --argjson remainingSeconds "$remaining" \
      '{unit:$unit,timer:$timer,minutes:$minutes,message:$message,label:$label,remaining:$remaining,remainingSeconds:$remainingSeconds,at:$at,atTime:$atTime}')
    reminders_json=$(jq -cn --argjson reminders "$reminders_json" --argjson item "$item_json" '$reminders + [$item]')
  done < <(active_reminder_timers "$now")

  if ((count == 1)); then
    tooltip="1 reminder"
  elif ((count > 1)); then
    tooltip="$count reminders"
  fi

  jq -cn --argjson count "$count" --arg tooltip "$tooltip" --argjson reminders "$reminders_json" '{count:$count,active:($count > 0),tooltip:$tooltip,reminders:$reminders}'
}

cancel_reminder() {
  local target=${1:-}
  local reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-reminders"
  local unit

  # Accept either "<unit>" or "<unit>.timer" — show --json emits both shapes.
  unit=${target%.timer}
  unit=${unit%.service}

  # Only ever touch this script's own units: the argument reaches here from a QML click handler, and `systemctl stop` on an arbitrary caller-supplied name is not something to hand out.
  if [[ -z $unit || $unit != quickshell-reminder-* ]]; then
    echo "reminder.sh: refusing to cancel non-reminder unit '${target}'" >&2
    return 1
  fi

  # Both units, not just the timer.
  systemctl --user stop "$unit.timer" "$unit.service" 2>/dev/null || true
  rm -f "$reminder_dir/$unit.message" 2>/dev/null || true
}

clear_reminders() {
  local units
  local reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-reminders"

  units=$(systemctl --user list-timers --all --no-legend --no-pager "quickshell-reminder-*.timer" 2>/dev/null | awk '{ print $(NF - 1), $NF }')

  if [[ -n $units ]]; then
    xargs -r systemctl --user stop <<<"$units" || true
  fi

  rm -f "$reminder_dir"/quickshell-reminder-*.message 2>/dev/null || true
  "$NOTIFY_BIN" -g 󰢌 "All reminders have been cleared"
}

usage() {
  echo "Usage: reminder.sh [-i|--interactive]"
  echo "       reminder.sh <minutes> [message]"
  echo "       reminder.sh show [-j|--json]"
  echo "       reminder.sh cancel <unit>"
  echo "       reminder.sh clear"
}

case ${1:-} in
-i | --interactive)
  open_interactive
  exit 0
  ;;
show | list)
  case ${2:-} in
  -j | --json)
    show_json
    ;;
  "")
    show_reminders
    ;;
  *)
    usage
    exit 1
    ;;
  esac
  exit 0
  ;;
clear)
  clear_reminders
  exit 0
  ;;
cancel | delete)
  cancel_reminder "${2:-}"
  exit 0
  ;;
esac

minutes=${1:-}
shift || true
message="$*"
custom_message="$message"

if [[ -z $minutes ]] || [[ ! $minutes =~ ^[0-9]+$ ]] || ((minutes == 0)); then
  usage
  exit 1
fi

unit_label=$( ((minutes == 1)) && echo "1 minute" || echo "${minutes} minutes")
# The alert card leads with what you asked to be reminded of.
alert_title=${message:-"Time's up"}
alert_body="${unit_label/%s/} reminder"

set_at=$(date +%s)
remind_at=$(date -d "+${minutes} minutes" +%H:%M)
unit="quickshell-reminder-${minutes}m-$set_at"
reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-reminders"
message_file="$reminder_dir/$unit.message"
confirmation="You'll be reminded at $remind_at"
confirmation_title="Reminder set for ${unit_label}"

mkdir -p "$reminder_dir"

if [[ -n $custom_message ]]; then
  printf "%s" "$custom_message" >"$message_file"
  confirmation_title="$custom_message in ${unit_label}"
fi

# Fires through alert.sh, not notification-send: a reminder that elapses while you are looking at another workspace must not auto-expire into nothing.
systemd-run --user --quiet --collect --on-active="${minutes}m" --unit="$unit" \
  bash -c '"$3" "$1" "$4" '"$BELL"' reminder "$5"; rm -f "$2"' bash "$alert_title" "$message_file" "$ALERT_BIN" "$alert_body" "$custom_message"

"$NOTIFY_BIN" -g "$BELL" "$confirmation_title" "$confirmation"
