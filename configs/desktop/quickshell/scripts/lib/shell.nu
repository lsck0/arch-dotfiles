# What the action scripts share: the live shell's config dir, its notification and a bounded IPC call.
# Callers import it with `const HERE = path self | path expand | path dirname`, so the ~/.local/bin links reach it.

export const SHELL_CONFIG = ($nu.home-dir | path join .config quickshell)
const IPC_TIMEOUT = "3s"

# Sent as the app the shell shows through dnd and keeps out of history (NotificationLogic.js ACTION_APP).
export def action-notify [glyph: string, title: string, body: string = ""]: nothing -> nothing {
    ^notify-send -a quickshell-action -u low -h $"string:lsck0-glyph:($glyph)" -- $title $body
}

# Bounded, so a shell that is down or hung never blocks the caller.
export def shell-call [target: string, ...args: string] {
    ^timeout $IPC_TIMEOUT quickshell ipc -p $SHELL_CONFIG call $target ...$args
}
