use module.nu *

export const options = {
    poster: {
        type: bool
        default: false
        doc: "This machine posts its Claude usage to the TRMNL panel; one poster per panel, a second would overwrite it"
        label: "Post to TRMNL"
    }
}

const SECRET = "configs/secrets/keys/trmnl-claude.env"

export def link [cfg: record] {
    if not $cfg.poster or not (secret-is-plaintext ($env.DOTFILES | path join $SECRET)) { return [] }
    [
        (file-render trmnl-claude.service (unit-dir | path join trmnl-claude.service) {DIR: $env.PWD})
        (unit-file trmnl-claude.timer --enable --now)
    ]
}
