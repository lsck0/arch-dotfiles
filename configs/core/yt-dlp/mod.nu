use module.nu *

export const meta = {packages: {pacman: [yt-dlp]}}

export def link [cfg: record] {
    [
        (files-into ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join yt-dlp) config)
        (link-commands yt-dlp.nu)
    ]
}
