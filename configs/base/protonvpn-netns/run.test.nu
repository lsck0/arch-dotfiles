#!/usr/bin/env -S nu --no-config-file
# The namespace entry (run.sh, root through a NOPASSWD sudo rule) and its two front ends (shim.sh, scripts/vpn.sh)
# hand a command on: every argument must arrive as typed, with nothing in it evaluated on the way, and run.sh must
# pass on only plain environment values. ip, setpriv, sudo and id are stubs, so nothing here needs the namespace.

const HERE = path self .
const RUN = $HERE | path join run.sh
const SHIM = $HERE | path join shim.sh
const VPN = $HERE | path join .. .. .. scripts vpn.sh
const NS = "protonvpn"
const RUN_INSTALLED = "/usr/local/lib/protonvpn-netns/run"
const STUBS = {
    ip: '#!/bin/sh
case "$1 $2" in
    "netns identify") echo "${STUB_NETNS:-}" ;;
    "netns exec") shift 3; exec "$@" ;;
    *) [ "${STUB_DOWN:-}" != 1 ] ;;
esac'
    setpriv: '#!/bin/sh
while [ "${1#--}" != "$1" ]; do shift; done
exec "$@"'
    sudo: '#!/bin/sh
printf "%s\n" "$@"'
    id: '#!/bin/sh
case "$1" in -nG) echo "users wheel" ;; *) exec /usr/bin/id "$@" ;; esac'
}

def fail [msg: string] { error make {msg: $"protonvpn-netns run.test: ($msg)"} }

def arguments [marker: path]: nothing -> list<string> {
    [
        $"--x=\(touch ($marker)\)" $"--x=$\(touch ($marker)\)" $"--x \(touch ($marker)\)" $"`touch ($marker)`"
        "--name=$env.HOME" "--user=$HOME" "-s" "--data={\"k\": [1, 2]}" "two words" "*" "true" "--"
    ]
}

def passed-check [what: string, run: record, want: list<string>, marker: path]: nothing -> nothing {
    if ($marker | path exists) { fail $"($what) evaluated an argument" }
    if $run.exit_code != 0 { fail $"($what) exited ($run.exit_code): ($run.stderr | str trim)" }
    let got = $run.stdout | lines
    if $got != $want { fail $"($what) passed ($got | to nuon), want ($want | to nuon)" }
}

def main [] {
    let work = mktemp --directory
    let marker = $work | path join evaluated
    let bin = $work | path join bin
    mkdir $bin
    for stub in ($STUBS | transpose name text) {
        $"($stub.text)\n" | save ($bin | path join $stub.name)
        chmod +x ($bin | path join $stub.name)
    }
    for name in [yt-dlp mpv-stream] { cp $SHIM ($bin | path join $name) }
    let args = arguments $marker
    let print_args = [/usr/bin/printf '%s\n']
    let stubbed = {PATH: $"($bin):/usr/bin", SUDO_USER: (^id -un | str trim)}
    try {
        with-env $stubbed {
            passed-check run.sh (^$RUN ...$print_args ...$args | complete) $args $marker

            let unsafe = {DISPLAY: $"$\(touch ($marker)\)", TERM: "../x y", LANG: "en_US.UTF-8", WAYLAND_DISPLAY: "wayland-1"}
            let kept = with-env $unsafe { ^$RUN /usr/bin/env | complete }
            let vars = $kept.stdout | lines | parse "{name}={value}" | transpose --header-row --as-record
            if ($marker | path exists) { fail "run.sh evaluated an environment value" }
            if $vars.DISPLAY != "" or $vars.TERM != "" { fail $"run.sh kept an unsafe value: ($vars | to nuon)" }
            if $vars.LANG != $unsafe.LANG or $vars.WAYLAND_DISPLAY != $unsafe.WAYLAND_DISPLAY {
                fail $"run.sh dropped a plain value: ($vars | to nuon)"
            }

            let down = with-env {STUB_DOWN: "1"} { ^$RUN ...$print_args reached | complete }
            if $down.exit_code == 0 or $down.stdout != "" { fail "run.sh ran a command with the namespace down" }
            let direct = with-env {SUDO_USER: ""} { ^$RUN ...$print_args reached | complete }
            if $direct.exit_code == 0 or $direct.stdout != "" { fail "run.sh ran a command without sudo" }

            passed-check "vpn outside" (^$VPN curl ...$args | complete) ([-n $RUN_INSTALLED curl] ++ $args) $marker
            let inside = with-env {STUB_NETNS: $NS} { ^$VPN ...$print_args ...$args | complete }
            passed-check "vpn inside" $inside $args $marker
            if (^$VPN | complete).exit_code != 2 { fail "vpn without a command must exit 2" }

            let shim = ^($bin | path join yt-dlp) ...$args | complete
            passed-check "shim" $shim ([-n $RUN_INSTALLED /usr/bin/yt-dlp] ++ $args) $marker
            let stream = ^($bin | path join mpv-stream) ...$args | complete
            passed-check "mpv-stream shim" $stream ([-n $RUN_INSTALLED /usr/bin/mpv --ytdl=yes] ++ $args) $marker
        }
    } catch {|err|
        rm --recursive --force $work
        error make {msg: $err.msg}
    }
    rm --recursive --force $work
}
