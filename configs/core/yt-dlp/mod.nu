use module.nu *

# vpn-routed reads both
export const meta = {packages: {pacman: [yt-dlp]}, inputs: [configs/secrets/keys/protonvpn-netns.conf /usr/local/bin/yt-dlp]}

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
    vpn_only: {
        type: bool
        default: true
        doc: ("Run yt-dlp only inside base/protonvpn-netns' namespace, never the bare route; without that namespace, "
            + "or off, yt-dlp and mpv's url playback run direct")
        label: "VPN only"
    }
}

const SHIM = "/usr/local/bin/yt-dlp"

# Whether yt-dlp is held to the namespace: the option, and the namespace's config or its shim present. desktop/mpv
# turns its own ytdl off by this as well.
export def vpn-routed [cfg: record]: nothing -> bool {
    $cfg.vpn_only and ([(secret-path keys protonvpn-netns.conf) $SHIM] | any { path exists })
}

export def link [cfg: record] {
    let values = {DOWNLOAD_DIR: $cfg.download_dir, CONTAINER: $cfg.container, SUB_LANGS: ($cfg.sub_langs | str join ",")}
    [
        (file-render config/config (xdg config yt-dlp config) $values)
        (if (vpn-routed $cfg) { link-commands scripts/yt-dlp.sh })
    ]
}
