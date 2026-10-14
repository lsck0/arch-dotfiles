#!/usr/bin/env -S nu --no-config-file
# yt-dlp only through ProtonVPN, fail closed: the protonvpn namespace's shim (base/protonvpn-netns) when it is deployed,
# else a refusal, never the bare route; for a machine without the tunnel's secret, where nothing in /usr/local/bin
# shadows /usr/bin/yt-dlp

const SHIM = "/usr/local/bin/yt-dlp"

def --wrapped main [...args: string]: nothing -> nothing {
    if not ($SHIM | path exists) {
        print --stderr "yt-dlp: no ProtonVPN namespace on this machine (base/protonvpn-netns), refusing the bare route"
        exit 1
    }
    exec $SHIM ...$args
}
