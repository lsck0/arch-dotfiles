use module.nu *

export const meta = {packages: {pacman: [yt-dlp]}}

export def link [cfg: record] {
    [
        (files-into (xdg config yt-dlp) config)
        (link-commands yt-dlp.nu)
    ]
}
