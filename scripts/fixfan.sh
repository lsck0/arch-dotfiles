#!/usr/bin/env bash
# Apply the two real fan fixes on this machine now: a quiet CPU power policy (EPP) and software fan
# control via it87 + a generated fancontrol curve. Re-runs itself with sudo.

set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

if [[ $EUID -ne 0 ]]; then
    exec sudo -E bash "$REPO/scripts/fixfan.sh" "$@"
fi

# fix 1: stop the pointless idle-boost to ~5GHz; balance_performance ramps on demand, idles low, no lag
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [[ -w "$epp" ]] && echo balance_performance >"$epp" || true
done
command -v tlp >/dev/null 2>&1 && tlp start >/dev/null 2>&1 || true
echo "power: EPP set to balance_performance"

# fix 2: load it87 and build a quiet-idle, ramp-on-heat fancontrol curve
bash "$REPO/configs/fancontrol/gen-fancontrol.sh"
