#!/usr/bin/env -S nu --no-config-file
# managed by arch-dotfiles/protonvpn-netns: shadows /usr/bin/<name> so it only runs inside the vpn namespace

const NAME = path self | path basename
const NS = "protonvpn"
const RUN = "/usr/local/lib/protonvpn-netns/run"

def --wrapped main [...args: string]: nothing -> nothing {
    let command = if $NAME == mpv-stream { [/usr/bin/mpv --ytdl=yes] } else { [$"/usr/bin/($NAME)"] }
    # already inside (ani-cli's yt-dlp): a second sudo would fail
    if (do { ^ip netns identify } | complete | get stdout | str trim) == $NS { exec ...$command ...$args }
    # the namespace entry is a wheel-only sudo rule: say so instead of sudo's "a password is required"
    if "wheel" not-in (^id -nG | split row " ") {
        print --stderr $"($NAME) runs only inside the vpn namespace, which needs a wheel login; ask an admin"
        exit 1
    }
    exec sudo -n $RUN ...$command ...$args
}
