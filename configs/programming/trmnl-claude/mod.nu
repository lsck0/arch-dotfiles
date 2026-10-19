use module.nu *

export const options = {
    poster: {
        type: bool
        default: false
        doc: "This machine posts its Claude usage to the TRMNL panel; one poster per panel, a second would overwrite it"
        label: "Post to TRMNL"
        scope: machine
    }
}

export def link [cfg: record] {
    let secret = $env.DOTFILES | path join secrets trmnl-claude.env
    if not $cfg.poster or not (secret-is-plaintext $secret) { return [] }
    [
        (file-render trmnl-claude.service (unit-dir | path join trmnl-claude.service) {DIR: ($env.PWD)})
        (unit-file trmnl-claude.timer --enable --now)
    ]
}
