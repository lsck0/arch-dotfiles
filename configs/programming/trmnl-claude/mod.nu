use module.nu *

export const options = {
    poster: {
        type: bool
        default: false
        doc: "This machine posts its Claude usage to the TRMNL panel; one poster per panel, a second would overwrite it"
        label: "Post to TRMNL"
    }
    interval_min: {
        type: int
        default: 15
        doc: "Minutes between posts; a divisor of 60, so the steps within each hour are even"
        label: "Post interval (min)"
        choices: [1 2 3 4 5 6 10 12 15 20 30]
    }
}

const SECRET = "configs/secrets/keys/trmnl-claude.env"

export def link [cfg: record] {
    if not $cfg.poster or not (secret-is-plaintext ($env.DOTFILES | path join $SECRET)) { return [] }
    [
        (unit-file services/trmnl-claude.service --values {DIR: $env.PWD})
        (unit-file services/trmnl-claude.timer --values {INTERVAL_MIN: $cfg.interval_min} --enable --now)
    ]
}
