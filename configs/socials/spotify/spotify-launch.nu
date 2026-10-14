#!/usr/bin/env -S nu --no-config-file
# the launcher entry: the user's spicetify copy (hook/spicetify-apply.nu) once there is one, else the stock client.
# apparmor.d's spotify profile attaches to /opt/spotify only, so the copy enters it through aa-exec (base/apparmor
# local/spotify); never unconfined while that profile is loaded, the stock client attaches by its path
# spotify's CEF ignores --ozone-platform-hint=auto and lands on XWayland at 1x, so under wayland name the platform
# outright (as teamspeak's module, hyprland then drives the scale); the copy skips /usr/bin/spotify's spotify-flags.conf

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
