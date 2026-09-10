#!/bin/bash
# Adapted from omarchy's bin/omarchy-reminder. Sets lightweight desktop
# notification reminders via systemd-run --user timers (ephemeral,
# --on-active relative timers; nothing persists across a reboot, matching
# upstream). Adaptations:
#   - omarchy-notification-send -> the sibling notification-send.sh helper.
#   - omarchy-shell -q omarchy.indicators refresh -> dropped. There is no
#     "push a refresh to a specific indicator" IPC here; the bar's Reminder
#     indicator (plugins/bar/indicators/Reminder.qml) polls on its own 5s
#     Timer instead, matching Dnd.qml/StayAwake.qml's established pattern
#     in this repo (see their own headers for why: no indicatorHost/
#     refreshRequested signal machinery is wired here).
#   - open_interactive(): omarchy-shell shell summon omarchy.reminders "{}"
#     -> quickshell ipc -p ~/.config/quickshell call shell summon
#     panel.reminders "{}".
#   - unit/state-dir prefix: omarchy-reminder-* -> quickshell-reminder-*,
#     ${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders ->
#     .../quickshell-reminders.

# omarchy:summary=Set and show lightweight desktop notification reminders
# omarchy:args=[-i|--interactive] | <minutes> [message] | show [-j|--json] | clear
# omarchy:examples=reminder.sh -i | reminder.sh 5 | reminder.sh 30 "Check the oven" | reminder.sh show | reminder.sh show --json | reminder.sh clear

set -euo pipefail

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
    "$(dirname "$(readlink -f "$0")")/notification-send.sh" -g 󰢌 "Upcoming reminders" "No outstanding reminders"
  else
    "$(dirname "$(readlink -f "$0")")/notification-send.sh" -g 󰢌 "Upcoming reminders" "${body%$'\n'}"
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

clear_reminders() {
  local units
  local reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-reminders"

  units=$(systemctl --user list-timers --all --no-legend --no-pager "quickshell-reminder-*.timer" 2>/dev/null | awk '{ print $(NF - 1), $NF }')

  if [[ -n $units ]]; then
    xargs -r systemctl --user stop <<<"$units" || true
  fi

  rm -f "$reminder_dir"/quickshell-reminder-*.message 2>/dev/null || true
  "$(dirname "$(readlink -f "$0")")/notification-send.sh" -g 󰢌 "All reminders have been cleared"
}

usage() {
  echo "Usage: reminder.sh [-i|--interactive]"
  echo "       reminder.sh <minutes> [message]"
  echo "       reminder.sh show [-j|--json]"
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
esac

minutes=${1:-}
shift || true
message="$*"
custom_message="$message"

if [[ -z $minutes ]] || [[ ! $minutes =~ ^[0-9]+$ ]] || ((minutes == 0)); then
  usage
  exit 1
fi

if [[ -z $message ]]; then
  message="Your ${minutes} minutes are up"
fi

set_at=$(date +%s)
remind_at=$(date -d "+${minutes} minutes" +%H:%M)
unit="quickshell-reminder-${minutes}m-$set_at"
reminder_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-reminders"
message_file="$reminder_dir/$unit.message"
confirmation="You'll be reminded at $remind_at"
confirmation_title="Reminder set for ${minutes} minutes"

mkdir -p "$reminder_dir"

if [[ -n $custom_message ]]; then
  printf "%s" "$custom_message" >"$message_file"
  confirmation_title="$custom_message in ${minutes} minutes"
fi

# Fires through scripts/alert.sh, not notification-send: a reminder that
# elapses while you are looking at another workspace must not auto-expire
# into nothing. alert.sh plays a sound and puts up the large top-left card
# that has to be dismissed by hand, falling back to a plain notification if
# quickshell is not running. Deliberate divergence from upstream omarchy,
# which uses a plain toast here.
# Absolute path, not the `alert` PATH symlink: systemd --user units get a
# minimal environment, and this must work before scripts/link.sh has run.
alert_bin="$(dirname "$(readlink -f "$0")")/alert.sh"
notification_bin="$(dirname "$(readlink -f "$0")")/notification-send.sh"

systemd-run --user --quiet --collect --on-active="${minutes}m" --unit="$unit" \
  bash -c '"$3" "Reminder" "$1" 󰢌; rm -f "$2"' bash "$message" "$message_file" "$alert_bin"

"$notification_bin" -g 󰢌 "$confirmation_title" "$confirmation"
