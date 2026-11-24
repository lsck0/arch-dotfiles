use module.nu *

export const meta = {packages: {pacman: [mpv mpv-mpris]}}

export const options = {
    ytdl_max_height: {
        type: int
        default: 2160
        doc: "Max video height yt-dlp fetches for a stream (ytdl-format height filter, pixels); applies to mpv-stream, plain mpv runs no yt-dlp"
        label: "Max stream quality (px)"
        scope: user
    }
    hwdec: {
        type: string
        default: "auto-safe"
        choices: [auto-safe auto vaapi nvdec vulkan no]
        doc: "Hardware video decoding (mpv hwdec)"
        label: "Hardware decoding"
    }
}

export def link [cfg: record] {
    let screenshots = $nu.home-dir | path join pictures screenshots
    [
        (file-render config/mpv.conf (xdg config mpv mpv.conf) {YTDL_MAX_HEIGHT: $cfg.ytdl_max_height, SCREENSHOTS: $screenshots, HWDEC: $cfg.hwdec})
        (exec mpv-screenshots [mkdir -p $screenshots] --creates $screenshots)
    ]
}
