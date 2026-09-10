#!/usr/bin/env bash

set -ex

sudo systemctl enable tlp.service

# Battery-having hardware defaults to TLP's real AC/BAT split (balanced on
# AC, power-saver on battery — see tlp.conf's CPU_ENERGY_PERF_POLICY_ON_*/
# PLATFORM_PROFILE_ON_* pairs). AC-only hardware (desktops, no
# /sys/class/power_supply/BAT*) has no meaningful "on battery" state, so it
# gets ac-only.tlp.conf instead, which pins performance regardless of
# source. Either way `tlp <state>` (toggles/toggle-powermode.sh) can force
# a different profile at runtime; TLP always resets to auto-detect on the
# next boot (tlp.service's `ExecStart=tlp init start`), so an override never
# persists past a reboot — matching both defaults being overridable but
# reboot-volatile.
if compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
    conf=bat.tlp.conf
else
    conf=ac-only.tlp.conf
fi
sudo ln -sf "${PWD}/${conf}" /etc/tlp.conf
