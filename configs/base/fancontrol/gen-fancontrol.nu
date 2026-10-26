#!/usr/bin/nu --no-config-file
# regenerated every boot: it87 shuffles hwmonN across reboots

const SYS = "/sys"
const HWMON = $"($SYS)/class/hwmon"
const BOARD_NAME_FILE = $"($SYS)/class/dmi/id/board_name"
const CONFIG = "/etc/fancontrol"
const BOARD = "X870E AORUS ELITE WIFI7"
const FORCE_ID = "0x8622"
const INTERVAL_S = 5
# Tctl jumps 15C within seconds on any burst; averaging 4 readings (20 s) keeps the fans from chasing it
const AVERAGE = 4
# the 9950X3D idles at 65-75C (Tjmax 95C): the ramp starts above that
const TEMP_MIN_C = 72
const TEMP_MAX_C = 90
# 16%: near-silent, but every fan spins, so a mis-identified channel never stalls
const PWM_FLOOR = 40
const PWM_START = 90
const PWM_MAX = 255

def read [file: path]: nothing -> string {
    try { open --raw $file | str trim } catch { "" }
}

def hwmon-find [pattern: string]: nothing -> any {
    ls $HWMON | get name | where { (read $"($in)/name") =~ $pattern } | path basename | get --optional 0
}

def bios [why: string]: nothing -> nothing {
    print --stderr $"fancontrol: ($why), leaving fans to the BIOS"
}

def main []: nothing -> nothing {
    if (read $BOARD_NAME_FILE) != $BOARD { return (bios $"not the ($BOARD)") }
    ^modprobe -q it87 $"force_id=($FORCE_ID)" ignore_resource_conflict=1 | complete | ignore
    let it87 = hwmon-find '^it8'
    if $it87 == null { return (bios "it87 did not load (check dmesg for the force_id)") }
    let k10 = hwmon-find '^k10temp$'
    if $k10 == null { return (bios "no k10temp sensor") }
    let tctl = glob $"($HWMON)/($k10)/temp*_label" | where { (read $in) == "Tctl" }
        | each { path basename | str replace "_label" "_input" } | get --optional 0 | default temp1_input
    let pwms = glob $"($HWMON)/($it87)/pwm[0-9]" | path basename | sort
    if ($pwms | is-empty) { return (bios "it87 exposes no pwm channels") }
    let every = {|value| $pwms | each { $"($it87)/($in)=($value)" } | str join " " }
    let devpath = {|h| $"($HWMON)/($h)/device" | path expand | str replace $"($SYS)/" "" }
    let original = $"($CONFIG).pre-dotfiles"
    if ($CONFIG | path exists) and not ($original | path exists) { ^cp -a $CONFIG $original }
    [
        "# managed by arch-dotfiles/configs/base/fancontrol; regenerated each boot by fancontrol-gen.service"
        $"INTERVAL=($INTERVAL_S)"
        $"DEVPATH=($it87)=(do $devpath $it87) ($k10)=(do $devpath $k10)"
        $"DEVNAME=($it87)=(read $'($HWMON)/($it87)/name') ($k10)=(read $'($HWMON)/($k10)/name')"
        $"FCTEMPS=(do $every $'($k10)/($tctl)')"
        # no FCFANS: the forced it87 reads 0 or 10000 rpm at random, and fancontrol kicks a 0 rpm fan to MINSTART
        $"MINTEMP=(do $every $TEMP_MIN_C)"
        $"MAXTEMP=(do $every $TEMP_MAX_C)"
        $"MINSTART=(do $every $PWM_START)"
        $"MINSTOP=(do $every $PWM_FLOOR)"
        $"MINPWM=(do $every $PWM_FLOOR)"
        $"MAXPWM=(do $every $PWM_MAX)"
        $"AVERAGE=(do $every $AVERAGE)"
    ] | str join "\n" | $"($in)\n" | save --force $CONFIG
    # no systemctl here: fancontrol.service must not be touched while it starts
    let curve = $"($PWM_FLOOR)/($PWM_MAX) floor to ($TEMP_MIN_C)C, full by ($TEMP_MAX_C)C"
    print --stderr $"fancontrol: ($pwms | length) fan channel\(s\) on ($it87) now follow Tctl \(($curve)\)"
}
