#!/usr/bin/env -S nu --no-config-file
# The toggles the bar's network panel, focus mode and the power selector run, walked through their state machines in
# a bwrap sandbox: every system command is a stub over a fake world (NM, rfkill, units, tlp, links, the bar), /run,
# /sys/class/net and /sys/class/bluetooth are fakes, the root helper runs from its source through a pkexec stub, and
# no real bus, network or home is reachable, so nothing on the machine flips. Each step checks the toggle's
# `get --json`, the world and the toasts; every mismatch is collected and reported at the end.

const TOGGLES = path self .
const REPO = path self ../..
const HELPER = path self ../../configs/core/toggles/toggle-root.nu
const DOT = path self ../dot.nu
const GRADING = path self ../../configs/desktop/color-grading/color-grading.py
const MAC = "aa:bb:cc:00:11:22"
const BT_TIMEOUT_S = 5

# Sourced by every stub: logs the call, then fails it when WORLD/fail/<name> holds "<regex>\t<exit>\t<stderr>" (exit
# "hang" sleeps instead) and the argv matches.
const STUB_COMMON = '
name=${0##*/}
printf "%s %s\n" "$name" "$*" >> "$WORLD/calls"
if [ -f "$WORLD/fail/$name" ]; then
  IFS="	" read -r pat code msg < "$WORLD/fail/$name"
  if printf "%s" "$*" | grep -Eq -- "$pat"; then
    [ "$code" = hang ] && exec sleep 60
    [ -n "$msg" ] && printf "%s\n" "$msg" >&2
    exit "$code"
  fi
fi
W=$WORLD
'

const STUBS = {
    nmcli: '
net=$(cat $W/networking)
rf() { sed -n "s/^$1 //p" $W/rfkill; }
devs() {
  while IFS=: read -r d t s; do
    [ -z "$d" ] && continue
    if [ "$net" = disabled ]; then s=unmanaged
    elif [ "$t" = wifi ] && [ "$(rf wlan)" = blocked ]; then s=unavailable; fi
    echo "$d:$t:$s"
  done < $W/devices
}
case "$*" in
  networking) echo "$net" ;;
  "networking on") echo enabled > $W/networking ;;
  "networking off") echo disabled > $W/networking ;;
  "-t -f TYPE device") devs | cut -d: -f2 ;;
  "-t -f DEVICE,TYPE,STATE device"|"-t -f DEVICE,TYPE,STATE dev status") devs ;;
  "-t -f DEVICE,STATE device") devs | cut -d: -f1,3 ;;
  "-t -f CONNECTIVITY general") if [ "$net" = disabled ]; then echo none; else cat $W/connectivity; fi ;;
  "-t -f WIFI-HW,WIFI radio") s=disabled; [ "$(rf wlan)" = unblocked ] && s=enabled; echo "$(cat $W/wifi-hw):$s" ;;
  "-t -f WIFI-HW radio") cat $W/wifi-hw ;;
  "-t -f WWAN-HW,WWAN radio") echo missing:disabled ;;
  "-t -f WWAN-HW radio") echo missing ;;
  "radio wifi on") sed -i "s/^wlan .*/wlan unblocked/" $W/rfkill ;;
  "radio wifi off") sed -i "s/^wlan .*/wlan blocked/" $W/rfkill ;;
  "device connect "*) sed -i "s/^$3:\([^:]*\):.*/$3:\1:connected/" $W/devices ;;
  "device disconnect "*) sed -i "s/^$3:\([^:]*\):.*/$3:\1:disconnected/" $W/devices ;;
  "-t -f GENERAL.CONNECTION,IP4.ADDRESS dev show "*) printf "GENERAL.CONNECTION:Wired 1\nIP4.ADDRESS[1]:192.0.2.10/24\n" ;;
  monitor) exec sleep infinity ;;
  *) echo "nmcli stub: unhandled $*" >&2; exit 64 ;;
esac'
    rfkill: '
case "$*" in
  "-rno TYPE,SOFT") cat $W/rfkill ;;
  "block all") sed -i "s/ .*/ blocked/" $W/rfkill ;;
  "unblock "*) sed -i "s/^$2 .*/$2 unblocked/" $W/rfkill ;;
  *) echo "rfkill stub: unhandled $*" >&2; exit 64 ;;
esac'
    systemctl: '
scope=system; args=""
for a in "$@"; do case $a in --user) scope=user ;; --quiet|--no-ask-password|--plain|--no-legend|--now) ;; *) args="$args $a" ;; esac; done
set -- $args
dir=$W/units/$scope; mkdir -p $dir
verb=$1; shift
case $verb in
  is-active) [ -e "$dir/$1" ] ;;
  cat) grep -qx "$1" $W/known-units ;;
  start|enable) for u; do touch "$dir/$u"; done ;;
  stop|disable) for u; do rm -f "$dir/$u"; done ;;
  list-units) eval "pat=\${$#}"; for u in $(ls $dir); do case $u in $pat) echo "$u loaded active waiting x" ;; esac; done ;;
  *) echo "systemctl stub: unhandled $verb $*" >&2; exit 64 ;;
esac'
    systemd-run: '
for a in "$@"; do case $a in --unit=*) mkdir -p $W/units/user; touch "$W/units/user/${a#--unit=}" ;; esac; done'
    pkexec: '
[ "$1" = /usr/local/bin/toggle-root ] || { echo "pkexec stub: not the helper: $1" >&2; exit 127; }
shift
PKEXEC_UID=$(/usr/bin/id -u) exec /usr/bin/nu --no-config-file "$HELPER" "$@"'
    tlp: '
case $1 in
  performance) c=0 ;; balanced) c=1 ;; power-saver) c=2 ;;
  start) rm -f /run/tlp/manual_mode; exit 0 ;;
  *) exit 64 ;;
esac
mkdir -p /run/tlp; echo $c > /run/tlp/manual_mode'
    wg-quick: '
case $1 in up) mkdir -p /sys/class/net/$2 ;; down) rmdir /sys/class/net/$2 ;; esac'
    protonvpn: '
case $1 in
  connect) mkdir -p /sys/class/net/proton0; echo Connected ;;
  disconnect) rmdir /sys/class/net/proton0 2>/dev/null; echo Disconnected ;;
esac'
    nm-online: ''
    bluetoothctl: '
case "$*" in
  show) p=$(cat $W/bt-power); grep -qx "bluetooth blocked" $W/rfkill && p=no; printf "Controller 00:00:00:00:00:01\n\tPowered: %s\n" "$p" ;;
  "power on") if grep -qx "bluetooth blocked" $W/rfkill; then echo "Failed to set power on: org.bluez.Error.Blocked"; exit 1; fi; echo yes > $W/bt-power ;;
  "power off") echo no > $W/bt-power ;;
esac'
    quickshell: '
case "$5 $6" in
  "toggles changed") echo "$7" >> $W/events ;;
  "notifications isDnd") cat $W/dnd ;;
  "notifications setDnd") if [ "$7" = true ]; then echo on > $W/dnd; else echo off > $W/dnd; fi ;;
  *) echo "$5 $6" >> $W/shell-calls ;;
esac'
    notify-send: '
u=normal
while [ $# -gt 2 ]; do case $1 in -u) u=$2; shift 2 ;; -a) shift 2 ;; *) break ;; esac; done
printf "%s\t%s\t%s\n" "$u" "$1" "$2" >> $W/toasts'
    ip: '
case "$*" in
  "-j -4 route show default"|"-j route show default") if [ "$(cat $W/networking)" = enabled ]; then cat $W/routes.json; else echo "[]"; fi ;;
  "-j neigh show "*) cat $W/neigh.json ;;
  *) echo "ip stub: unhandled $*" >&2; exit 64 ;;
esac'
    id: '
if [ "$1" = -nG ]; then echo "$(/usr/bin/id -un) wheel"; else exec /usr/bin/id "$@"; fi'
    busctl: 'echo "b false"'
    hyprctl: ''
    color-grading: '
case "$*" in
  "get nightlight") cat $XDG_RUNTIME_DIR/nightlight 2>/dev/null || echo off ;;
  "set nightlight "*) echo $3 > $XDG_RUNTIME_DIR/nightlight ;;
  status) printf "{\"preset\":\"%s\",\"presets\":[{\"name\":\"off\",\"label\":\"Off\"},{\"name\":\"default\",\"label\":\"Default\"},{\"name\":\"grayscale\",\"label\":\"Grayscale\"}]}\n" "$(cat $W/preset)" ;;
  "set preset "*) echo $3 > $W/preset ;;
esac'
}

# dot set/apply as trust-network calls them: the option lives in the world, a write leaves the system part pending.
const DOT_STUB = '
def main [] {}
def "main set" [...args: string, --json, --machine, --no-system, --default] {
    let option = $env.WORLD | path join option.nuon
    if $json {
        {modules: [{options: [{key: trusted_gateways, value: (open $option)}]}]} | to json --raw | print
        return
    }
    $"dot set ($args | str join (char space))\n" | save --append ($env.WORLD | path join calls)
    $args.1 | from nuon | save --force $option
    exit 3
}
def "main apply" [...args: string, --system] {
    "dot apply --system\n" | save --append ($env.WORLD | path join calls)
    exit 3
}'

def world [w: path, ...parts: string]: nothing -> path { $w | path join world ...$parts }

def put [w: path, file: string, text: string]: nothing -> nothing { $text | save --force (world $w $file) }

def peek [w: path, file: string]: nothing -> string {
    let f = world $w $file
    if ($f | path exists) { open --raw $f | str trim } else { "" }
}

def runtime [w: path]: nothing -> path { $w | path join run user (^id -u | str trim) }

def stub-write [path: path, body: string]: nothing -> nothing {
    $"#!/bin/sh\n($STUB_COMMON)($body)\n" | save --force $path
    chmod +x $path
}

# A machine on its home-less wired link: networking on, wifi and bluetooth radios unblocked, the default firewall.
def world-init [w: path]: nothing -> nothing {
    let files = {
        home/.config/dotfiles/profile.nuon: "{capabilities: [secrets]}"
        etc-dotfiles/platform: "luca-pc\n"
        etc-wg/wg0.conf: ""
        net/enp16s0/address: "02:00:00:00:00:01\n"
        net/enp16s0/statistics/rx_bytes: "1000\n"
        net/enp16s0/statistics/tx_bytes: "1000\n"
        world/networking: enabled
        world/rfkill: "wlan unblocked\nbluetooth unblocked\n"
        world/devices: "enp16s0:ethernet:connected\nwlan0:wifi:disconnected\n"
        world/connectivity: full
        world/wifi-hw: enabled
        world/known-units: ([tor-router.service portmaster.service fw-inbound.service fw-lockdown.service bluetooth.service] | str join "\n")
        world/routes.json: '[{"dst":"default","gateway":"192.0.2.1","dev":"enp16s0","metric":100}]'
        world/neigh.json: $'[{"dst":"192.0.2.1","dev":"enp16s0","lladdr":"($MAC | str uppercase)","state":["REACHABLE"]}]'
        world/dnd: off
        world/preset: off
        world/bt-power: yes
        world/option.nuon: "[]"
        dot.nu: $DOT_STUB
        toggle-root.nu: (open --raw $HELPER | str replace "@APPROVAL_DIR@" "/run/toggle-auth" | str replace "@APPROVAL_MINUTES@" "5")
    }
    for f in ($files | transpose path text) {
        let path = $w | path join $f.path
        mkdir ($path | path dirname)
        $f.text | save --force $path
    }
    mkdir (runtime $w) (world $w fail) (world $w units system) (world $w units user) ($w | path join bin) ($w | path join dispatcher)
    mkdir ($w | path join bt hci0) ($w | path join net enp16s0 device) ($w | path join net wlan0 device)
    mkdir ($w | path join home .cache) ($w | path join home .local state)
    for u in [fw-inbound.service portmaster.service bluetooth.service] { touch (world $w units system $u) }
    for s in ($STUBS | transpose name body) { stub-write ($w | path join bin $s.name) $s.body }
}

# Runs argv in the sandbox: the home hidden, the repo read-only with dot.nu and color-grading.py stubbed and the
# secrets hidden (locked), the fakes over /run and /sys, no network, a clean environment.
def --wrapped sb [w: path, ...argv: string]: nothing -> record {
    let home = $w | path join home
    (^bwrap --dev-bind / / --tmpfs $nu.home-dir --ro-bind $REPO $REPO
        --ro-bind ($w | path join dot.nu) $DOT --ro-bind ($w | path join bin color-grading) $GRADING
        --tmpfs ($REPO | path join configs secrets)
        --bind ($w | path join run) /run --bind ($w | path join net) /sys/class/net --bind ($w | path join bt) /sys/class/bluetooth
        --bind ($w | path join etc-dotfiles) /etc/dotfiles --bind ($w | path join etc-wg) /etc/wireguard
        --bind ($w | path join dispatcher) /etc/NetworkManager/dispatcher.d
        --proc /proc --unshare-user --unshare-pid --unshare-ipc --unshare-net --die-with-parent --clearenv
        --setenv PATH $"($w | path join bin):/usr/bin" --setenv HOME $home --setenv LANG C.UTF-8
        --setenv XDG_CONFIG_HOME ($home | path join .config) --setenv XDG_CACHE_HOME ($home | path join .cache)
        --setenv XDG_STATE_HOME ($home | path join .local state) --setenv XDG_RUNTIME_DIR $"/run/user/(^id -u | str trim)"
        --setenv WORLD ($w | path join world) --setenv HELPER ($w | path join toggle-root.nu)
        ...$argv) | complete
}

def --wrapped toggle [w: path, name: string, ...args: string]: nothing -> record {
    sb $w ($TOGGLES | path join $"toggle-($name).nu") ...$args
}

def rec [w: path, name: string]: nothing -> record {
    let r = toggle $w $name get --json
    try { $r.stdout | from json } catch { {state: $"unparsed: ($r.stdout)($r.stderr)", available: null, on: null} }
}

# A soft check: the mismatch is recorded with both sides and the run goes on.
def expect [w: path, what: string, got: any, want: any]: nothing -> nothing {
    if $got != $want {
        $"($what): got ($got | to nuon), want ($want | to nuon)\n" | save --append ($w | path join failures)
    }
}

# Runs the toggle and checks that it succeeded and its state is now want.
def switched [w: path, want: string, name: string, ...args: string]: nothing -> nothing {
    let what = [$name ...$args] | str join " "
    expect $w $"($what) exit" (toggle $w $name ...$args).exit_code 0
    expect $w $what (rec $w $name).state $want
}

# What the stubs appended to a world file since the last take: the toasts, the bar's events.
def take [w: path, file: string]: nothing -> list<string> {
    let f = world $w $file
    let lines = if ($f | path exists) { open --raw $f | lines } else { [] }
    rm --force $f
    $lines
}

def inject [w: path, command: string, pattern: string, code: string, message: string = ""]: nothing -> nothing {
    $"($pattern)\t($code)\t($message)\n" | save --force (world $w fail $command)
}

def heal [w: path, command: string]: nothing -> nothing { rm --force (world $w fail $command) }

# The toggle run while command's calls matching pattern fail with code and message, healed after: its exit code and
# the toasts it left.
def failing [w: path, command: string, pattern: string, code: string, message: string, name: string, ...args: string]: nothing -> list<any> {
    inject $w $command $pattern $code $message
    let r = toggle $w $name ...$args
    heal $w $command
    [$r.exit_code (take $w toasts)]
}

# What a reboot resets: /run (the runtime dir, tlp's record), links made at runtime, user units; NM's networking
# state and rfkill's blocks are restored by their services, units enabled stay.
def reboot [w: path]: nothing -> nothing {
    rm --recursive --force ($w | path join run)
    mkdir (runtime $w)
    for l in [wg0 proton0] { rm --force --recursive ($w | path join net $l) }
    rm --force --recursive (world $w units user)
    mkdir (world $w units user)
    rm --force (world $w units system tor-router.service)
}

def unit-up [w: path, unit: string, --user]: nothing -> bool {
    world $w units (if $user { "user" } else { "system" }) $unit | path exists
}

def state-file [w: path, name: string]: nothing -> path { $w | path join home .local state toggles $name }

def route-cases [w: path]: nothing -> nothing {
    expect $w "route starts direct" (rec $w route | select state on available) {state: direct, on: false, available: true}
    # wg0 up before offline: offline takes it down and leaving brings it back
    toggle $w vpn on | ignore
    expect $w "vpn on" (rec $w vpn).state on
    take $w toasts | ignore
    take $w events | ignore

    switched $w offline route set offline
    expect $w "offline networking" (peek $w networking) disabled
    expect $w "offline radios blocked" (peek $w rfkill) "wlan blocked\nbluetooth blocked"
    expect $w "offline wg0 down" ($w | path join net wg0 | path exists) false
    expect $w "offline record" (open --raw (state-file $w offline-rfkill) | lines) [wlan bluetooth]
    expect $w "offline vpn record" (open --raw (state-file $w offline-vpn) | str trim) on
    expect $w "offline toast" (take $w toasts | last) "normal\tRoute\tOffline"
    expect $w "offline pings the bar" ("toggle-route.nu" in (take $w events)) true

    # headphones while offline: a radio unblocked keeps the route offline
    switched $w on bluetooth on
    expect $w "offline survives bluetooth" (rec $w route).state offline

    reboot $w
    expect $w "offline survives a reboot" (rec $w route).state offline
    expect $w "offline record survives a reboot" (state-file $w offline-rfkill | path exists) true

    take $w toasts | ignore
    switched $w direct route set direct
    expect $w "radios restored" (peek $w rfkill) "wlan unblocked\nbluetooth unblocked"
    expect $w "networking on" (peek $w networking) enabled
    expect $w "wg0 back" ($w | path join net wg0 | path exists) true
    expect $w "records gone" ([offline-rfkill offline-vpn] | each { state-file $w $in | path exists }) [false false]
    expect $w "direct toast" (take $w toasts) ["normal\tRoute\tDirect"]
    toggle $w vpn off | ignore

    # networking turned on outside the switch: the record still lifts its blocks on the next switch
    toggle $w route set offline | ignore
    put $w networking enabled
    expect $w "networking on outside: not offline" (rec $w route).state direct
    toggle $w route set tor | ignore
    expect $w "outside on: record lifted" (peek $w rfkill) "wlan unblocked\nbluetooth unblocked"
    expect $w "outside on: record gone" (state-file $w offline-rfkill | path exists) false
    toggle $w route set direct | ignore

    # tor: the helper starts it unmarked; a dispatcher's marker is dropped
    touch ($w | path join run persona-tor)
    take $w toasts | ignore
    switched $w tor route set tor
    expect $w "tor unit" (unit-up $w tor-router.service) true
    expect $w "tor marker dropped" ($w | path join run persona-tor | path exists) false
    # proton over a user's tor: tor stops once proton0 is up, portmaster with it (no pre-up dispatcher here)
    switched $w proton route set proton
    expect $w "proton: tor stopped" (unit-up $w tor-router.service) false
    expect $w "proton: portmaster stopped" (unit-up $w portmaster.service) false
    expect $w "proton toasts" (take $w toasts) ["normal\tRoute\tTor" "normal\tRoute\tProtonVPN"]
    let r = toggle $w route set direct
    expect $w "proton off" [$r.exit_code (rec $w route).state ($w | path join net proton0 | path exists)] [0 direct false]
    touch (world $w units system portmaster.service)

    # a dispatcher's tor (marked) stays for the dispatcher to stop
    toggle $w route set tor | ignore
    touch ($w | path join run persona-tor)
    toggle $w route set proton | ignore
    expect $w "dispatcher tor kept" (unit-up $w tor-router.service) true
    toggle $w route set direct | ignore
    expect $w "direct stops tor" (unit-up $w tor-router.service) false
    touch (world $w units system portmaster.service)
    take $w toasts | ignore

    # failures roll back to the state before and say so
    let r = failing $w protonvpn '^connect' 1 "Connection failed: no server" route set proton
    expect $w "proton failure" [$r.0 ($r.1 | last | str starts-with "critical\tRoute\tSwitch to ProtonVPN failed, now Direct: connect failed")] [1 true]
    expect $w "proton failure: route stays" (rec $w route).state direct
    touch (world $w units system portmaster.service)

    let r = failing $w pkexec 'tor-start' 126 "Error executing command as another user: Request dismissed" route set tor
    expect $w "tor cancelled" [$r.0 ($r.1 | last)] [1 "critical\tRoute\tSwitch to Tor failed, now Direct: authorization cancelled"]
    expect $w "tor cancelled: route stays" (rec $w route).state direct

    # a second press while one switch runs is reported, never queued
    let lock = runtime $w | path join toggles toggle-route.nu.flock
    mkdir ($lock | path dirname)
    let holder = job spawn { ^flock --close $lock sleep 29.25 }
    sleep 300ms
    let r = toggle $w route set tor
    expect $w "busy exit" $r.exit_code 75
    expect $w "busy toast" (take $w toasts) ["normal\tRoute\tStill switching"]
    expect $w "busy: route stays" (rec $w route).state direct
    job kill $holder
    ^pkill -f $"flock --close ($lock) sleep" | complete | ignore
    ^pkill -x -f "sleep 29.25" | complete | ignore

    # a press for the route already in effect (the bar's state was stale) still reports back
    let r = toggle $w route set direct
    expect $w "same route" [$r.exit_code (take $w events | last) (take $w toasts)] [0 toggle-route.nu ["normal\tRoute\tDirect"]]

    expect $w "toggle never cycles into offline" (["direct" "proton" "tor"] | each {|from|
        toggle $w route set $from | ignore
        toggle $w route toggle | ignore
        let to = (rec $w route).state
        if $to == offline { toggle $w route set direct | ignore }
        $to
    }) [proton tor direct]
    toggle $w route set direct | ignore
    # no persona dispatcher here to restore it
    touch (world $w units system portmaster.service)
    take $w toasts | ignore
}

def focus-cases [w: path]: nothing -> nothing {
    switched $w on focus on
    expect $w "focus: dnd" (peek $w dnd) on
    expect $w "focus: keep-awake" (unit-up $w toggle-keep-awake.service --user) true
    expect $w "focus: nightlight" (open --raw (runtime $w | path join nightlight) | str trim) on
    expect $w "focus: grading" (peek $w preset) grayscale
    expect $w "focus toast" (take $w toasts) ["normal\tFocus mode\tTurned on"]

    reboot $w
    expect $w "focus survives a reboot" (rec $w focus).state on
    expect $w "reboot reset keep-awake" (rec $w keep-awake).state off
    let r = toggle $w focus reapply
    expect $w "reapply exit" $r.exit_code 0
    expect $w "reapply keep-awake" (rec $w keep-awake).state on
    expect $w "reapply nightlight" (rec $w nightlight).state on
    expect $w "reapply is quiet" (take $w toasts) []

    switched $w off focus off
    expect $w "focus off parts" ([dnd keep-awake nightlight] | each {|t| (rec $w $t).state }) [off off off]
    expect $w "focus off grading" (peek $w preset) off
    expect $w "reapply after off does nothing" [(toggle $w focus reapply).exit_code (rec $w keep-awake).state] [0 off]

    # a part on before focus stays on after it, and reapply leaves it to its owner
    toggle $w keep-awake on | ignore
    toggle $w focus on | ignore
    reboot $w
    toggle $w focus reapply | ignore
    expect $w "own keep-awake not reapplied" (rec $w keep-awake).state off
    toggle $w focus off | ignore

    # a part that cannot be turned off keeps focus on and its record for the next try
    toggle $w focus on | ignore
    let r = failing $w color-grading.py '^set nightlight off' 1 "hyprsunset: no socket" focus off
    expect $w "stuck part" [$r.0 ($r.1 | last | str starts-with "critical\tFocus mode\tSwitch to off failed")] [1 true]
    expect $w "stuck part keeps focus on" (rec $w focus).state on
    toggle $w focus off | ignore
    expect $w "retry clears focus" (rec $w focus).state off
    take $w toasts | ignore
}

def powermode-cases [w: path]: nothing -> nothing {
    expect $w "powermode starts auto" ((toggle $w powermode get).stdout | str trim) auto
    let r = toggle $w powermode set balanced
    expect $w "balanced exit" $r.exit_code 0
    expect $w "balanced from tlp" (rec $w powermode | select state on) {state: balanced, on: true}
    expect $w "balanced toast" (take $w toasts) ["normal\tPower mode\tBalanced"]
    # the bar's selector names auto as a value of its own, never empty
    toggle $w powermode set performance | ignore
    expect $w "performance" ((toggle $w powermode get).stdout | str trim) performance
    # tlp restarted (its service, a resume): its record is gone and so is the forced mode
    rm ($w | path join run tlp manual_mode)
    expect $w "tlp restart is auto" (rec $w powermode).state auto
    toggle $w powermode set power-saver | ignore
    expect $w "power-saver" (rec $w powermode).state power-saver
    expect $w "saver flag" (open --raw (runtime $w | path join toggles powersaver) | str trim) on
    expect $w "saver reloads the bar" ((peek $w shell-calls) | str contains "shell reloadPowerMode") true
    take $w toasts | ignore

    let r = failing $w tlp '^performance' 1 "Error: tlp is disabled" powermode set performance
    expect $w "tlp failure" $r [1 ["critical\tPower mode\tSwitch to Performance failed, now Power saver: Error: tlp is disabled"]]
    expect $w "tlp failure: mode stays" (rec $w powermode).state power-saver

    toggle $w powermode set auto | ignore
    expect $w "auto clears tlp's record" [($w | path join run tlp manual_mode | path exists) (rec $w powermode).state] [false auto]
    expect $w "auto: saver off" (open --raw (runtime $w | path join toggles powersaver) | str trim) off
    toggle $w powermode set balanced | ignore
    reboot $w
    expect $w "reboot is auto" (rec $w powermode).state auto
    expect $w "toggle cycles from auto" ([1 2 3 4] | each { toggle $w powermode toggle | ignore; (rec $w powermode).state }) [balanced performance power-saver auto]
    expect $w "unknown mode exits 2" (toggle $w powermode set turbo).exit_code 2
    take $w toasts | ignore
}

def trust-cases [w: path]: nothing -> nothing {
    expect $w "away: offered, off" (rec $w trust-network | select state available) {state: off, available: true}
    # an owner's locked secrets: the mac never goes to the option, the public repo's platform file
    let r = toggle $w trust-network on
    expect $w "owner locked: on refused" [$r.exit_code (open (world $w option.nuon))] [1 []]
    expect $w "owner locked toast" (take $w toasts | last) "critical\tTrusted network\tSwitch to on failed: configs/secrets is locked: unlock it to trust this network"

    # a login without secrets keeps the list in the option
    let profile = $w | path join home .config dotfiles profile.nuon
    "{capabilities: []}" | save --force $profile
    let r = toggle $w trust-network on
    expect $w "trust exit" $r.exit_code 0
    expect $w "trust stores the gateway" (open (world $w option.nuon)) [$MAC]
    expect $w "trust toast says pending" (take $w toasts) ["normal\tTrusted network\tSaved; the network changes with the next dot apply --system"]
    # the system apply marks the link
    "enp16s0\n" | save --force ($w | path join run trusted-network)
    expect $w "trusted: on" (rec $w trust-network).state on
    let r = toggle $w trust-network off
    expect $w "untrust exit" $r.exit_code 0
    expect $w "untrust drops the gateway" (open (world $w option.nuon)) []
    rm ($w | path join run trusted-network)
    take $w toasts | ignore

    # a gateway trusted by home_gateways is home: not offered, and on refuses
    "enp16s0\n" | save --force ($w | path join run home-network)
    "enp16s0\n" | save --force ($w | path join run trusted-network)
    expect $w "home: hidden" (rec $w trust-network | select state available) {state: off, available: false}
    let r = toggle $w trust-network off
    expect $w "home: off refused" [$r.exit_code (open (world $w option.nuon))] [0 []]
    rm ($w | path join run home-network) ($w | path join run trusted-network)
    take $w toasts | ignore

    # off a gateway nobody listed: refused with the reason, nothing written
    "enp16s0\n" | save --force ($w | path join run trusted-network)
    let r = toggle $w trust-network off
    expect $w "unlisted off exit" $r.exit_code 1
    expect $w "unlisted off toast" (take $w toasts | last) "critical\tTrusted network\tSwitch to off failed: configs/secrets is locked: unlock it to change the trusted list"
    rm ($w | path join run trusted-network)

    # no default route (offline): nothing to trust
    put $w networking disabled
    expect $w "no uplink: hidden" (rec $w trust-network | select state available) {state: off, available: false}
    put $w networking enabled
    "{capabilities: [secrets]}" | save --force $profile
}

# a socket-activated service: off takes its socket too, or the next client starts it again
def service-cases [w: path]: nothing -> nothing {
    $"(peek $w known-units)\ndocker.service\ndocker.socket\n" | save --force (world $w known-units)
    touch (world $w units system docker.socket)
    expect $w "docker: a listening socket is on" (rec $w docker | select state available) {state: on, available: true}
    toggle $w docker off | ignore
    expect $w "docker off takes the socket" [(unit-up $w docker.service) (unit-up $w docker.socket)] [false false]
    toggle $w docker on | ignore
    expect $w "docker on brings both" [(unit-up $w docker.service) (unit-up $w docker.socket)] [true true]
    take $w toasts | ignore
}

# reapply replays the saved expressions in the order they were saved: a mirror after a scale stays a mirror
def monitor-cases [w: path]: nothing -> nothing {
    let dir = runtime $w | path join toggles
    mkdir $dir
    let scale = 'hl.monitor({ output = "HDMI-A-1", scale = 1.5 })'
    let mirror = 'hl.monitor({ output = "HDMI-A-1", mirror = "DP-1" })'
    $" ($scale)" | save --force ($dir | path join monitor-HDMI-A-1-scale)
    $" ($mirror)" | save --force ($dir | path join monitor-HDMI-A-1-layout)
    ^touch -d "2026-01-01 00:00:00" ($dir | path join monitor-HDMI-A-1-scale)
    ^touch -d "2026-01-01 00:00:01" ($dir | path join monitor-HDMI-A-1-layout)
    let before = peek $w calls | lines | length
    let r = toggle $w monitor-scale reapply
    let evals = peek $w calls | lines | skip $before | where { $in | str starts-with "hyprctl eval " }
        | str replace "hyprctl eval " ""
    expect $w "monitor reapply exit" $r.exit_code 0
    expect $w "reapply keeps the saved order" $evals [$scale $mirror]
    rm ($dir | path join monitor-HDMI-A-1-scale) ($dir | path join monitor-HDMI-A-1-layout)
}

def radio-cases [w: path]: nothing -> nothing {
    expect $w "wifi on" (rec $w wifi | select state available) {state: on, available: true}
    toggle $w wifi off | ignore
    expect $w "wifi off" [(rec $w wifi).state (peek $w rfkill | lines | first)] [off "wlan blocked"]
    put $w wifi-hw missing
    let r = toggle $w wifi on
    expect $w "wifi without hardware" [$r.exit_code (take $w toasts | last)] [1 "critical\tWi-Fi\tSwitch to on failed: no wifi hardware"]
    put $w wifi-hw enabled
    toggle $w wifi on | ignore
    expect $w "ethernet" (rec $w ethernet | select state available) {state: on, available: true}
    toggle $w ethernet off | ignore
    expect $w "ethernet off" (rec $w ethernet).state off
    toggle $w ethernet on | ignore
    expect $w "mobile hidden" (rec $w mobile).available false

    # a hung bluetoothd: the switch gives up after its timeout and says so
    let r = failing $w bluetoothctl '^power off' hang "" bluetooth off
    expect $w "bluetooth hang" [$r.0 ($r.1 | last | str starts-with "critical\tBluetooth\tSwitch to off failed")] [1 true]
    rm --force --recursive ($w | path join bt hci0)
    expect $w "no adapter: hidden" (rec $w bluetooth | select state available) {state: off, available: false}
    mkdir ($w | path join bt hci0)

    # a broken probe is an error, never a quiet off or a radio gone missing
    inject $w nmcli '^-t -f ' 8 "Error: NetworkManager is not running."
    for t in [wifi ethernet mobile] {
        expect $w $"nmcli down: ($t) error" (rec $w $t | select state available) {state: error, available: true}
    }
    let r = toggle $w wifi toggle
    expect $w "nmcli down: toggle refused" [$r.exit_code (take $w toasts | last)] [1 "critical\tWi-Fi\tSwitch failed: its state cannot be read: Error: NetworkManager is not running."]
    heal $w nmcli
    expect $w "nmcli back: wifi on" (rec $w wifi | select state available) {state: on, available: true}

    # vpn up fails in the helper: the cause reaches the toast
    let r = failing $w wg-quick '^up' 1 "RTNETLINK answers: Operation not permitted" vpn on
    expect $w "vpn failure" [$r.0 ($r.1 | last)] [1 "critical\tHomelab VPN\tSwitch to on failed: RTNETLINK answers: Operation not permitted"]
}

def firewall-cases [w: path]: nothing -> nothing {
    expect $w "firewall default" (rec $w firewall | select state text) {state: default, text: Default}
    toggle $w firewall set restrictive | ignore
    expect $w "restrictive" (rec $w firewall).state restrictive
    toggle $w firewall set permissive | ignore
    expect $w "permissive" (rec $w firewall | select state text) {state: permissive, text: Permissive}
    expect $w "lowering toast" (take $w toasts | last) "critical\tFirewall\tLowered to Permissive"
    toggle $w firewall set default | ignore
    expect $w "raise default" (rec $w firewall).state default
    take $w toasts | ignore
}

def status-cases [w: path]: nothing -> nothing {
    let names = [route vpn anonymous-socks bluetooth wifi ethernet mobile firewall trust-network portal]
    let r = sb $w ($TOGGLES | path join status.nu) ...$names
    let list = try { $r.stdout | from json } catch { [] }
    expect $w "status lists every network toggle" ($list | get name) ($names | sort)
    expect $w "status: no error" ($list | where state == error | get name) []
    expect $w "portal hidden without the dispatcher" ($list | where name == portal | get 0.available?) false
    let theme = rec $w theme-mode
    expect $w "theme without a palette is an error" ($theme | select state available) {state: error, available: true}
}

def main [] {
    if (which bwrap | is-empty) { error make {msg: "toggles.test: bwrap is not installed"} }
    let w = mktemp --directory --tmpdir dot-toggles-test-XXXXXX
    let outcome = try {
        world-init $w
        status-cases $w
        route-cases $w
        focus-cases $w
        powermode-cases $w
        trust-cases $w
        radio-cases $w
        firewall-cases $w
        service-cases $w
        monitor-cases $w
        null
    } catch {|err| $err.rendered? | default $err.msg }
    let failures = if ($w | path join failures | path exists) { open --raw ($w | path join failures) } else { "" }
    let calls = peek $w calls | lines | last 15 | str join "\n"
    # TOGGLES_TEST_KEEP=1 keeps the world for a look
    if $env.TOGGLES_TEST_KEEP? == "1" { print -e $"toggles.test: kept ($w)" } else { rm --recursive --force $w }
    if $outcome != null { error make {msg: $"toggles.test: ($outcome)"} }
    if $failures != "" { error make {msg: $"toggles.test:\n($failures)last stub calls:\n($calls)"} }
}
