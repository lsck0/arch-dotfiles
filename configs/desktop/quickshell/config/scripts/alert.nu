#!/usr/bin/env -S nu --no-config-file
# hand-dismissed alert card, a notification when the shell cannot show it; kind: reminder (snooze)

const HERE = path self | path expand | path dirname
use ($HERE | path join lib shell.nu) [SHELL_CONFIG shell-call sounds-on]

const SOUND_DIR = "sounds"
const SOUND_FALLBACK = "reminder"
const GLYPH_BELL = "\u{F0020}"
const SOUND_TIMEOUT = "3s"
# NotificationLogic.js ALERT_APP: kept in history and, critical, shown through dnd until dismissed
const FALLBACK_APP = "alert"

# payload: {title, body, glyph, kind, message} as json, one argv word that starts with '{': nu re-parses an argv word
# that starts with '-' as flags, even after --, so free text never goes as a positional of its own
def main [payload?: string] {
    let fields = if $payload == null { {} } else { $payload | from json }
    let text = {|key, fallback| $fields | get -o $key | default $fallback | into string }
    let title = do $text title "Reminder"
    let body = do $text body ""
    let glyph = do $text glyph $GLYPH_BELL
    let kind = do $text kind ""
    let snooze_message = do $text message ""
    let payload = {title: $title, body: $body, glyph: $glyph, kind: $kind, message: $snooze_message} | to json -r
    let summoned = shell-call shell summon panel.alert $payload | complete
    if ($summoned.stdout | str trim) != "ok" {
        try { ^notify-send -a $FALLBACK_APP -u critical -h $"string:lsck0-glyph:($glyph)" -- $title $body }
    }
    # foreground: the systemd unit kills background children on exit
    let cue = $SHELL_CONFIG | path join $SOUND_DIR $"(if $kind == "" { $SOUND_FALLBACK } else { $kind }).oga"
    if ($cue | path exists) and (sounds-on) { ^timeout $SOUND_TIMEOUT pw-play --media-role Notification $cue | complete | ignore }
}
