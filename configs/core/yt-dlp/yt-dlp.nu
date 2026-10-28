#!/usr/bin/env -S nu --no-config-file

const SHIM = "/usr/local/bin/yt-dlp"

def --wrapped main [...args: string]: nothing -> nothing {
    if not ($SHIM | path exists) {
        print --stderr "yt-dlp: no ProtonVPN namespace on this machine (base/protonvpn-netns), refusing the bare route"
        exit 1
    }
    exec $SHIM ...$args
}
