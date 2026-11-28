# What the action scripts share: the live shell's config dir, its notification, a bounded IPC call, an atomic
# write for the state files the shell watches, the JSON lines a helper streams to it and the epoch arithmetic of the
# wall-clock timers.
# A caller in another module imports the checkout copy by its relative path (hyprland's record.nu, screenshot.nu); one
# here imports it with `const HERE = path self | path expand | path dirname`, so the ~/.local/bin links reach it.

export const SHELL_CONFIG = ($nu.home-dir | path join .config quickshell)
const IPC_TIMEOUT = "3s"

# The options link writes for the shell (prefs-config in mod.nu); {} when missing, so each key keeps its default.
export def prefs-load []: nothing -> record {
    try { open ($SHELL_CONFIG | path join prefs.json) | into record } catch { {} }
}

# The sounds option: false silences the alert and pomodoro chimes.
export def sounds-on []: nothing -> bool { (prefs-load | get --optional sounds) != false }

# Sent as the app the shell shows through dnd (NotificationLogic.js ACTION_APP); a shown one still goes to history.
# --urgency normal for the one that should be noticed (a timer's end), which stays up longer than a low confirmation.
export def action-notify [
    glyph: string, title: string, body: string = "", --urgency: string = "low"
]: nothing -> nothing {
    ^notify-send -a quickshell-action -u $urgency -h $"string:lsck0-glyph:($glyph)" -- $title $body
}

# Bounded, so a shell that is down or hung never blocks the caller; a caller with a tighter budget passes --timeout.
export def shell-call [target: string, ...args: string, --timeout: string = $IPC_TIMEOUT] {
    ^timeout $timeout quickshell ipc -p $SHELL_CONFIG call $target ...$args
}

# Through a temp per writer, so a watcher never reads half a file and two writers never share one temp.
export def file-save-atomic [path: path]: any -> nothing {
    let body = $in
    mkdir ($path | path dirname)
    let temp = $"($path).($nu.pid).tmp"
    $body | save -f $temp
    mv -f $temp $path
}

export def json-save-atomic [value: record, path: path]: nothing -> nothing { $value | to json -r | file-save-atomic $path }

# A helper's progress for the shell: one JSON line on stdout, or {error} as the last one.
export def json-emit [line: record]: nothing -> nothing { print ($line | to json --raw) }

export def json-fail [message: string]: nothing -> nothing {
    json-emit {error: $message}
    exit 1
}

export def epoch-now []: nothing -> int { date now | into int | $in // 1_000_000_000 }

# systemd's OnCalendar form, in UTC so a dst change or a new timezone keeps the epoch
export def epoch-to-calendar [epoch: int]: nothing -> string {
    $epoch * 1_000_000_000 | into datetime | format date '%Y-%m-%d %H:%M:%S UTC'
}
