#!/usr/bin/env -S nu --no-config-file
# capgemini [url...]: the work sites in their own chromium profile, away from the personal cookies and firefox's blockers

const PORTAL = "https://arc.capgemini.com/"
# --ozone-platform-hint=auto: native wayland, so the pipewire screencast portal works for teams screen share
# --no-first-run: a profile's first start blocks on a placeholder terms of service dialog
# --disable-features=DIPS: bounce tracking mitigation wipes zpa-auth.net/zscaler.com state and the sso asks again
# --password-store=gnome-libsecret: under hyprland chromium would pick the basic store, a fixed key
const FLAGS = [--ozone-platform-hint=auto --no-first-run --disable-features=DIPS --password-store=gnome-libsecret]

def main [...urls: string]: nothing -> nothing {
    # entra id and pingfederate treat tor exits as anonymous ips and block or re-prompt the sign-in
    if (^systemctl is-active -q tor-router.service | complete).exit_code == 0 {
        try { ^notify-send -u critical Capgemini "tor-router is on, turn it off first" }
        error make {msg: "capgemini: tor-router is on, turn it off first"}
    }
    # a proton exit is a foreign datacenter ip pingid and zscaler may refuse; only a warning, auto-vpn enables it itself
    if ("/sys/class/net/proton0" | path exists) {
        try { ^notify-send Capgemini "ProtonVPN is on: if the sign-in fails or keeps asking for PingID, turn it off" }
    }
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join capgemini chromium
    exec chromium ...$FLAGS $"--user-data-dir=($data)" ...(if ($urls | is-empty) { [$PORTAL] } else { $urls })
}
