#!/usr/bin/env -S nu --no-config-file
# managed by arch-dotfiles/protonvpn-netns: installed as /usr/local/bin/<name>, ahead of /usr/bin in PATH, so <name> only
# ever runs through the protonvpn namespace (run.nu); with the tunnel down it refuses instead of going out over the real
# link. mpv-stream is mpv with its ytdl hook, which plain mpv leaves off; every other name runs its /usr/bin twin

const NAME = path self | path basename
const NS = "protonvpn"
const RUN = "/usr/local/lib/protonvpn-netns/run"

def --wrapped main [...args: string]: nothing -> nothing {
    let command = if $NAME == mpv-stream { [/usr/bin/mpv --ytdl=yes] } else { [$"/usr/bin/($NAME)"] }
    # already inside (ani-cli's or a namespaced mpv's yt-dlp): run it directly, a second sudo would only fail there
    if (do { ^ip netns identify } | complete | get stdout | str trim) == $NS { exec ...$command ...$args }
    exec sudo -n $RUN ...$command ...$args
}
