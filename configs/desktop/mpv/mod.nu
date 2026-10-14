use module.nu *

export const meta = {packages: {pacman: [mpv mpv-mpris]}}

export def link [cfg: record] {
    let screenshots = $nu.home-dir | path join pictures screenshots
    [
        (files-into ($nu.home-dir | path join .config mpv) mpv.conf)
        (exec mpv-screenshots [mkdir -p $screenshots] --creates $screenshots)
    ]
}
