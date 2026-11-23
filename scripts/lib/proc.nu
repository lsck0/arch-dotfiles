# Running another program only for its exit code or a toast, for scripts that run from the checkout; a copy outside it
# (dispatcher.d, /usr/local/bin, the lock's command dir) keeps its own.

# Whether argv ran and exited 0; its output is dropped.
export def --wrapped succeeds [...argv: string]: nothing -> bool {
    (do { run-external ...$argv } | complete).exit_code == 0
}

# A best-effort desktop notification: whether it was shown, false without notify-send or a notification daemon.
export def notify [app: string, title: string, body: string = "", --urgency: string = "normal"]: nothing -> bool {
    if (which notify-send | is-empty) { return false }
    succeeds notify-send -a $app -u $urgency -- $title $body
}
