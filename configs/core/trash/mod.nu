use module.nu *

export const meta = {packages: {pacman: [trash-cli]}}

export const options = {
    retention_days: {
        type: int
        default: 1
        doc: "Days trash-empty.timer keeps a deleted file before purging it, trash-empty(1)'s days argument"
        label: "Trash retention (days)"
        scope: user
    }
}

export def link [cfg: record] {
    [
        (shell-aliases trash)
        (unit-file config/trash-empty.service --values {RETENTION_DAYS: $cfg.retention_days})
        (unit-timer trash-empty.timer "Daily user trash cleanup" --calendar daily --delay 1h --enable --now)
    ]
}
