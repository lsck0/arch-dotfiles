#!/usr/bin/env -S nu --no-config-file
# the user's spicetify copy once there is one, entering apparmor.d's /opt/spotify-only profile through aa-exec
# spotify's CEF ignores --ozone-platform-hint=auto and lands on XWayland at 1x, so the platform is named outright

const STOCK = "/usr/bin/spotify"
const APPARMOR_ENABLED = "/sys/module/apparmor/parameters/enabled"
const WAYLAND_FLAGS = [--enable-features=UseOzonePlatform --ozone-platform=wayland]

def --wrapped main [...args: string]: nothing -> nothing {
    let flags = if ($env.WAYLAND_DISPLAY? | is-not-empty) { $WAYLAND_FLAGS } else { [] }
    let copy = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join spotify-patched spotify
    if ($copy | path exists) {
        if (^aa-exec -p spotify -- true | complete).exit_code == 0 {
            exec aa-exec -p spotify -- $copy ...$flags ...$args
        }
        # apparmor off: nothing confines the stock client either
        let apparmor = try { open --raw $APPARMOR_ENABLED | str trim } catch { "" }
        if $apparmor != "Y" { exec $copy ...$flags ...$args }
    }
    exec $STOCK ...$flags ...$args
}
