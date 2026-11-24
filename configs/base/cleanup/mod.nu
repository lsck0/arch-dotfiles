use module.nu *

export const options = {
    journal_max_use: {
        type: string
        default: "1G"
        doc: "Total disk space the systemd journal may keep, journald.conf(5) size syntax"
        label: "Max journal size"
    }
    journal_retention: {
        type: string
        default: "3month"
        doc: "Age past which journal entries are dropped even with space left, journald.conf(5) MaxRetentionSec"
        label: "Journal retention"
    }
}

# scripts/lib/fetch.nu's pinned downloads, as root and as the user; it touches a blob on reuse, so the age counts
# from the last apply that needed it
const FETCH_CACHE_AGE = "60d"
const FETCH_CACHE_ROOT = "/var/cache/dotfiles/fetch"
const FETCH_CACHE_USER = "%C/dotfiles/fetch"

def fetch-cache-rule [dir: string]: nothing -> string { $"e ($dir) - - - ($FETCH_CACHE_AGE)\n" }

export def system [cfg: record] {
    let journal = {MAX_USE: $cfg.journal_max_use, RETENTION: $cfg.journal_retention}
    [
        (file-render config/journald-size.conf /etc/systemd/journald.conf.d/00-size.conf $journal
            --then (unit-restart systemd-journald.service))
        # read by rootless podman too; a container already created keeps the driver it was made with
        (file-copy config/containers-log.conf /etc/containers/containers.conf.d/10-log.conf)
        (file-text /etc/tmpfiles.d/dotfiles-fetch.conf (fetch-cache-rule $FETCH_CACHE_ROOT))
    ]
}

export def link [cfg: record] {
    [
        (link-commands scripts/home-sweep.nu)
        (file-text (xdg config user-tmpfiles.d dotfiles-fetch.conf) (fetch-cache-rule $FETCH_CACHE_USER))
        (unit-file services/home-sweep.service)
        (unit-timer home-sweep.timer "Weekly home directory log sweep" --calendar weekly --delay 1h --enable --now)
        (if (which nix-collect-garbage | is-not-empty) {
            [
                (unit-file services/nix-gc.service)
                (unit-timer nix-gc.timer "Weekly nix store garbage collection" --calendar weekly --delay 1h --enable --now)
            ]
        })
    ]
}
