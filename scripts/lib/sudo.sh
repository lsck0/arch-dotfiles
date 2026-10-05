# shellcheck shell=bash
# sudo_keepalive_start: one prompt, then the caller's tty timestamp stays warm until the caller exits; no global timestamp

# well under sudo's default 5 min timestamp_timeout
SUDO_KEEPALIVE_INTERVAL_S=50

sudo_keepalive_start() {
    sudo -v
    # polls the caller's pid, so a crash ends it too; detached from the caller's output so a log tee never waits on it
    (while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep "$SUDO_KEEPALIVE_INTERVAL_S"; done) </dev/null >/dev/null 2>&1 &
}
