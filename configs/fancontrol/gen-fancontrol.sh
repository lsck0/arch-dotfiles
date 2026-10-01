#!/usr/bin/env bash
# Load it87 and generate a safe /etc/fancontrol, then enable fancontrol. Every fan follows the CPU (Tctl)
# on a gentle curve with an airflow floor, so no pwmconfig and no per-fan mapping is needed.

set -euo pipefail

FORCE_ID=0x8622
# quiet below MINTEMP, ramp to full by MAXTEMP; ryzen Tctl idles ~45C and boosts to ~85C under load
MINTEMP=55
MAXTEMP=88
# 20% floor: quiet but keeps every fan (and any pump) spinning so a mis-identified channel never stalls
FLOOR_PWM=51
START_PWM=90

hwmon_by_name() {
    local want=$1 h
    for h in /sys/class/hwmon/hwmon*; do
        [[ "$(cat "$h/name" 2>/dev/null)" == $want ]] && { basename "$h"; return 0; }
    done
    return 1
}

# the hwmon's device path relative to /sys, how fancontrol re-resolves it across reboots
devpath_of() { (cd "/sys/class/hwmon/$1/device" && pwd -P | sed 's#^/sys/##'); }

modprobe -q it87 "force_id=$FORCE_ID" ignore_resource_conflict=1 2>/dev/null || true

it87=$(hwmon_by_name 'it8*') || { echo "fancontrol: it87 did not load (check dmesg for the force_id), leaving fans to the BIOS" >&2; exit 0; }
k10=$(hwmon_by_name 'k10temp') || { echo "fancontrol: no k10temp sensor, leaving fans to the BIOS" >&2; exit 0; }

# Tctl is the control temperature; fall back to temp1
tctl=temp1_input
for lbl in /sys/class/hwmon/"$k10"/temp*_label; do
    [[ "$(cat "$lbl" 2>/dev/null)" == Tctl ]] && { tctl="$(basename "${lbl%_label}")_input"; break; }
done

pwms=()
for p in /sys/class/hwmon/"$it87"/pwm[0-9]; do [[ -e "$p" ]] && pwms+=("$(basename "$p")"); done
(( ${#pwms[@]} )) || { echo "fancontrol: it87 exposes no pwm channels, leaving fans to the BIOS" >&2; exit 0; }

fctemps=() fcfans=() mintemp=() maxtemp=() minstart=() minstop=() minpwm=() maxpwm=()
for pwm in "${pwms[@]}"; do
    fan="fan${pwm#pwm}_input"
    fctemps+=("$it87/$pwm=$k10/$tctl")
    [[ -e "/sys/class/hwmon/$it87/$fan" ]] && fcfans+=("$it87/$pwm=$it87/$fan")
    mintemp+=("$it87/$pwm=$MINTEMP"); maxtemp+=("$it87/$pwm=$MAXTEMP")
    minstart+=("$it87/$pwm=$START_PWM"); minstop+=("$it87/$pwm=$FLOOR_PWM")
    minpwm+=("$it87/$pwm=$FLOOR_PWM"); maxpwm+=("$it87/$pwm=255")
done

[[ -e /etc/fancontrol && ! -e /etc/fancontrol.pre-dotfiles ]] && cp -a /etc/fancontrol /etc/fancontrol.pre-dotfiles
{
    echo "# managed by arch-dotfiles/configs/fancontrol; regenerate with fixfan.sh"
    echo "INTERVAL=10"
    echo "DEVPATH=$it87=$(devpath_of "$it87") $k10=$(devpath_of "$k10")"
    echo "DEVNAME=$it87=$(cat /sys/class/hwmon/"$it87"/name) $k10=$(cat /sys/class/hwmon/"$k10"/name)"
    echo "FCTEMPS=${fctemps[*]}"
    echo "FCFANS=${fcfans[*]}"
    echo "MINTEMP=${mintemp[*]}"
    echo "MAXTEMP=${maxtemp[*]}"
    echo "MINSTART=${minstart[*]}"
    echo "MINSTOP=${minstop[*]}"
    echo "MINPWM=${minpwm[*]}"
    echo "MAXPWM=${maxpwm[*]}"
} >/etc/fancontrol

systemctl enable --now fancontrol.service
echo "fancontrol: ${#pwms[@]} fan channel(s) on $it87 now follow Tctl (${FLOOR_PWM}/255 floor, full by ${MAXTEMP}C)"
