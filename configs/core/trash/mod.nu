use module.nu *

export const meta = {packages: {pacman: [trash-cli]}}

export const options = {
    retention_days: {
        type: int
        default: 1
        doc: "Days trash-empty.timer keeps a deleted file before purging it, trash-empty(1) --trash-dir day argument"
        label: "Trash retention (days)"
        scope: user
    }
}

export def link [cfg: record] {
    [
        (file-render trash-empty.service (unit-dir | path join trash-empty.service) {RETENTION_DAYS: $cfg.retention_days})
        (unit-file trash-empty.timer --enable --now)
    ]
}
