#!/usr/bin/env -S nu --no-config-file
# capgemini [url...]: the work sites in their own chromium profile, away from the personal cookie jar and firefox's
# script blockers; without a url it opens just the ARC portal (teams/outlook are .desktop actions). the managed policy
# (configs/desktop/chromium) lets only the microsoft 365 and ping sign-in use third-party cookies; camera, mic and
# screen share ask per origin. this profile alone also allows the zscaler/arc sites (mod.nu, site-settings.json)

const PORTAL = "https://arc.capgemini.com/"
# --ozone-platform-hint=auto: native wayland, so the pipewire screencast portal works (teams screen share) and 4k scales
# --no-first-run: chromium builds open a placeholder "Additional Terms of Service" dialog on a profile's first start,
# which holds the window until it is answered
# --disable-features=DIPS: bounce tracking mitigation (DIPS, chromium's name for it up to 154) wipes the state of sites
# only ever redirected through, zpa-auth.net and zscaler.com in arc's sign-in, and the strict sso then asks again
# --password-store=gnome-libsecret: cookies and saved passwords sealed by the login keyring; under hyprland chromium
# would otherwise pick the basic store, a fixed key
const FLAGS = [--ozone-platform-hint=auto --no-first-run --disable-features=DIPS --password-store=gnome-libsecret]

def main [...urls: string]: nothing -> nothing {
    # entra id and pingfederate treat tor exits as anonymous ips and block or re-prompt the sign-in
    if (^systemctl is-active -q tor-router.service | complete).exit_code == 0 {
        try { ^notify-send -u critical Capgemini "tor-router is on, turn it off first" }
        error make {msg: "capgemini: tor-router is on, turn it off first"}
    }
    # a proton exit is a datacenter ip in another country: pingid's risk rules and zscaler's access policy may refuse it
    # or ask again. only a warning, auto-vpn turns it on by itself on every untrusted network (configs/base/protonvpn)
    if ("/sys/class/net/proton0" | path exists) {
        try { ^notify-send Capgemini "ProtonVPN is on: if the sign-in fails or keeps asking for PingID, turn it off" }
    }
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join capgemini chromium
    exec chromium ...$FLAGS $"--user-data-dir=($data)" ...(if ($urls | is-empty) { [$PORTAL] } else { $urls })
}
