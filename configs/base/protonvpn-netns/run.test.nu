#!/usr/bin/env -S nu --no-config-file
# The namespace entry (run.sh, root through a NOPASSWD sudo rule) and its two front ends (shim.sh, scripts/vpn.sh)
# hand a command on: every argument must arrive as typed, with nothing in it evaluated on the way, and run.sh must
# pass on only plain environment values. ip, setpriv, sudo and id are stubs, so nothing here needs the namespace.

use std/assert
use ../../../scripts/launchers.test.nu [hostile]

const HERE = path self .
const RUN = $HERE | path join run.sh
const SHIM = $HERE | path join shim.sh
const VPN = $HERE | path join .. .. .. scripts vpn.sh
const NS = "protonvpn"
const RUN_INSTALLED = "/usr/local/lib/protonvpn-netns/run"
const STUBS = {
    ip: '#!/bin/sh
[ -z "${STUB_LOG:-}" ] || echo "$*" >> "$STUB_LOG"
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

def passed-check [what: string, run: record, want: list<string>, marker: path]: nothing -> nothing {
    assert (not ($marker | path exists)) $"($what) evaluated an argument"
    assert equal $run.exit_code 0 $"($what) exited ($run.exit_code): ($run.stderr | str trim)"
    assert equal ($run.stdout | lines) $want $"($what) passed the wrong argv"
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
    let args = hostile $marker
    let print_args = [/usr/bin/printf '%s\n']
    let stubbed = {PATH: $"($bin):/usr/bin", SUDO_USER: (^id -un | str trim)}
    try {
        with-env $stubbed {
            passed-check run.sh (^$RUN ...$print_args ...$args | complete) $args $marker

            let unsafe = {DISPLAY: $"$\(touch ($marker)\)", TERM: "../x y", LANG: "en_US.UTF-8", WAYLAND_DISPLAY: "wayland-1"}
            let kept = with-env $unsafe { ^$RUN /usr/bin/env | complete }
            let vars = $kept.stdout | lines | parse "{name}={value}" | transpose --header-row --as-record
            assert (not ($marker | path exists)) "run.sh evaluated an environment value"
            assert equal ($vars | select DISPLAY TERM) {DISPLAY: "", TERM: ""} "run.sh kept an unsafe value"
            assert equal ($vars | select LANG WAYLAND_DISPLAY) ($unsafe | select LANG WAYLAND_DISPLAY) "run.sh dropped a plain value"

            # fail closed: with the namespace or its link gone the command never runs, nor is the namespace entered
            let ran = $work | path join ran
            let command = $bin | path join command
            $"#!/bin/sh\ntouch ($ran)\n" | save $command
            chmod +x $command
            let log = $work | path join ip.log
            let down = with-env {STUB_DOWN: "1", STUB_LOG: $log} { ^$RUN $command | complete }
            let asked = open --raw $log | lines
            assert ($down.exit_code != 0 and not ($ran | path exists)) "run.sh ran a command with the namespace down"
            assert ($"-n ($NS) link show wg-($NS)" in $asked and not ($asked | any { $in starts-with "netns exec" })) (
                $"run.sh did not check the link before entering: ip calls ($asked | to nuon)")
            rm $log
            let up = with-env {STUB_LOG: $log} { ^$RUN $command | complete }
            assert ($up.exit_code == 0 and ($ran | path exists)) $"the command stub did not run with the namespace up: ($up.stderr)"
            let direct = with-env {SUDO_USER: ""} { ^$RUN ...$print_args reached | complete }
            assert ($direct.exit_code != 0 and $direct.stdout == "") "run.sh ran a command without sudo"

            passed-check "vpn outside" (^$VPN curl ...$args | complete) ([-n $RUN_INSTALLED /usr/bin/curl] ++ $args) $marker
            let inside = with-env {STUB_NETNS: $NS} { ^$VPN ...$print_args ...$args | complete }
            passed-check "vpn inside" $inside $args $marker
            assert equal (^$VPN | complete).exit_code 2 "vpn without a command must exit 2"
            assert equal (^$VPN vpn-test-missing-command | complete).exit_code 127 "vpn with a missing command must exit 127"

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
