#!/usr/bin/env -S nu --no-config-file
# hand-dismissed alert card, a notification when the shell cannot show it; kind: reminder (snooze)

const HERE = path self | path expand | path dirname
use ($HERE | path join lib shell.nu) [SHELL_CONFIG shell-call]

const SOUND_DIR = "sounds"
const SOUND_FALLBACK = "reminder"
const GLYPH_BELL = "\u{F0020}"
const SOUND_TIMEOUT = "3s"
# NotificationLogic.js ALERT_APP: kept in history and, critical, shown through dnd until dismissed
const FALLBACK_APP = "alert"

# untyped: nu parses a lone argv word true, false or a number as that value, which a string parameter refuses
def main [title?, body?, glyph?, kind?, snooze_message?] {
    let text = {|value, fallback| $value | default $fallback | into string }
    let title = do $text $title "Reminder"
    let body = do $text $body ""
    let glyph = do $text $glyph $GLYPH_BELL
    let kind = do $text $kind ""
    let snooze_message = do $text $snooze_message ""
    let payload = {title: $title, body: $body, glyph: $glyph, kind: $kind, message: $snooze_message} | to json -r
    let summoned = shell-call shell summon panel.alert $payload | complete
    if ($summoned.stdout | str trim) != "ok" {
        try { ^notify-send -a $FALLBACK_APP -u critical -h $"string:lsck0-glyph:($glyph)" -- $title $body }
    }
    # foreground: the systemd unit kills background children on exit
    let cue = $SHELL_CONFIG | path join $SOUND_DIR $"(if $kind == "" { $SOUND_FALLBACK } else { $kind }).oga"
    if ($cue | path exists) { ^timeout $SOUND_TIMEOUT pw-play --media-role Notification $cue | complete | ignore }
}
