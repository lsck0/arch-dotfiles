#!/usr/bin/env -S nu --no-config-file
# spotify's CEF ignores --ozone-platform-hint=auto and lands on XWayland at 1x, so the platform is named outright

use spotify-reload.nu [DEVTOOLS_PORT]

const STOCK = "/usr/bin/spotify"
const APPARMOR_ENABLED = "/sys/module/apparmor/parameters/enabled"
const WAYLAND_FLAGS = [--enable-features=UseOzonePlatform --ozone-platform=wayland]

# loudness normalization, merged here since spotify rewrites its prefs on exit, so dot's apply only lands while it is closed
const LOUDNESS = {audio.normalize_v2: "true", audio.loudness.environment: "1"}

def loudness-merge []: nothing -> nothing {
    if (^pgrep -x spotify | complete).exit_code == 0 { return }
    let users = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join spotify Users
    for prefs in (glob ($users | path join * prefs)) {
        let lines = open --raw $prefs | lines
        let missing = $LOUDNESS | transpose key value | where {|kv| not ($lines | any { str starts-with $"($kv.key)=" }) }
        if ($missing | is-not-empty) {
            $lines ++ ($missing | each { $"($in.key)=($in.value)" }) | str join "\n" | $"($in)\n" | save --force $prefs
        }
    }
}

def --wrapped main [...args: string]: nothing -> nothing {
    loudness-merge
    let flags = [$"--remote-debugging-port=($DEVTOOLS_PORT)"] ++ (if ($env.WAYLAND_DISPLAY? | is-not-empty) { $WAYLAND_FLAGS } else { [] })
    let copy = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join spotify-patched spotify
    if ($copy | path exists) {
        if (which aa-exec | is-not-empty) and (^aa-exec -p spotify -- true | complete).exit_code == 0 {
            exec aa-exec -p spotify -- $copy ...$flags ...$args
        }
        let apparmor = try { open --raw $APPARMOR_ENABLED | str trim } catch { "" }
        if $apparmor != "Y" { exec $copy ...$flags ...$args }
    }
    exec $STOCK ...$flags ...$args
}
