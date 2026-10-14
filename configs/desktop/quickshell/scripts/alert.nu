#!/usr/bin/env -S nu --no-config-file
# hand-dismissed alert card, a notification when the shell cannot show it; kind: reminder (snooze) or pomodoro (stop)

const SOUND = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
const GLYPH_BELL = "\u{F0020}"
const TIMEOUT = "3s"
const SOUND_TIMEOUT = "10s"

def main [title = "Reminder", body = "", glyph = $GLYPH_BELL, kind = "", snooze_message = ""] {
    let payload = {title: $title, body: $body, glyph: $glyph, kind: $kind, message: $snooze_message} | to json -r
    let summoned = ^timeout $TIMEOUT quickshell ipc -p ($nu.home-dir | path join .config quickshell) call shell summon panel.alert $payload
        | complete
    if not ($summoned.stdout =~ ok) {
        # never drop the alert
        try { ^notify-send -a quickshell-action -u low -h $"string:omarchy-glyph:($glyph)" $title $body }
    }
    # foreground: the systemd unit kills background children on exit
    if ($SOUND | path exists) { ^timeout $SOUND_TIMEOUT pw-play $SOUND | complete | ignore }
}
