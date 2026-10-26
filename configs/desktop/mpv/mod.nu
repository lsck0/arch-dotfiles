use module.nu *

export const meta = {packages: {pacman: [mpv mpv-mpris]}}

export const options = {
    ytdl_max_height: {
        type: int
        default: 2160
        doc: "Max video height mpv's bundled yt-dlp fetches for a stream URL, mpv ytdl-format height filter (pixels)"
        label: "Max stream quality (px)"
        scope: user
    }
}

export def link [cfg: record] {
    let screenshots = $nu.home-dir | path join pictures screenshots
    [
        (file-render mpv.conf (xdg config mpv mpv.conf) {YTDL_MAX_HEIGHT: $cfg.ytdl_max_height})
        (exec mpv-screenshots [mkdir -p $screenshots] --creates $screenshots)
    ]
}
