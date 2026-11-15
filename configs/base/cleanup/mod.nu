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
    container_log_max_mb: {
        type: int
        default: 50
        doc: "Largest log file podman keeps per container, in MiB; container output stays out of the journal"
        label: "Max container log (MiB)"
        min: 1
    }
}

const BYTES_PER_MIB = 1048576
# scripts/lib/fetch.nu's pinned downloads, as root and as the user; it touches a blob on reuse, so the age counts
# from the last apply that needed it
const FETCH_CACHE_AGE = "60d"
const FETCH_CACHE_ROOT = "/var/cache/dotfiles/fetch"
const FETCH_CACHE_USER = "%C/dotfiles/fetch"

def fetch-cache-rule [dir: string]: nothing -> string { $"e ($dir) - - - ($FETCH_CACHE_AGE)\n" }

export def system [cfg: record] {
    let journal = {MAX_USE: $cfg.journal_max_use, RETENTION: $cfg.journal_retention}
    [
        (file-render journald-size.conf /etc/systemd/journald.conf.d/00-size.conf $journal
            --then (unit-restart systemd-journald.service))
        # read by rootless podman too; a container already created keeps the driver it was made with
        (file-render containers-log.conf /etc/containers/containers.conf.d/10-log.conf {
            LOG_SIZE_MAX_BYTES: ($cfg.container_log_max_mb * $BYTES_PER_MIB)
        })
        (file-text /etc/tmpfiles.d/dotfiles-fetch.conf (fetch-cache-rule $FETCH_CACHE_ROOT))
    ]
}

export def link [cfg: record] {
    [
        (link-commands home-sweep.nu)
        (file-text (xdg config user-tmpfiles.d dotfiles-fetch.conf) (fetch-cache-rule $FETCH_CACHE_USER))
        (unit-file home-sweep.service)
        (unit-file home-sweep.timer --enable --now)
        (if (which nix-collect-garbage | is-not-empty) {
            [(unit-file nix-gc.service) (unit-file nix-gc.timer --enable --now)]
        })
    ]
}
