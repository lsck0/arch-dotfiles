use module.nu *

export const meta = {packages: {pacman: [yt-dlp]}}

export const options = {
    download_dir: {
        type: string
        default: "~/downloads/yt-dlp"
        doc: "Directory downloads and the download archive go to"
        label: "Download directory"
        scope: user
    }
    container: {
        type: string
        default: mp4
        doc: "Container merged video and audio streams go into, --merge-output-format"
        label: "Container"
        choices: [avi flv mkv mov mp4 webm]
        scope: user
    }
    sub_langs: {
        type: list<string>
        default: ["en.*" "de.*"]
        doc: "Subtitle languages embedded, as regexes, --sub-langs"
        label: "Subtitle languages"
        scope: user
    }
}

export def link [cfg: record] {
    let values = {DOWNLOAD_DIR: $cfg.download_dir, CONTAINER: $cfg.container, SUB_LANGS: ($cfg.sub_langs | str join ",")}
    [
        (file-render config/config (xdg config yt-dlp config) $values)
        (link-commands scripts/yt-dlp.sh)
    ]
}
