use module.nu *

export const meta = {packages: {pacman: [starship]}}

export const options = {
    scan_timeout_ms: {
        type: int
        default: 500
        doc: "Milliseconds starship waits for a directory scan (project file detection) before giving up, starship.toml scan_timeout"
        label: "Prompt scan timeout (ms)"
        scope: user
    }
}

export def link [cfg: record] {
    file-render starship.toml (xdg config starship.toml) {SCAN_TIMEOUT_MS: $cfg.scan_timeout_ms}
}
