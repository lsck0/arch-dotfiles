#!/usr/bin/env -S nu --no-config-file
# gpu-section: the [gpu] text for /etc/gamemode.ini, the amd level only on an amd card.

use mod.nu [gpu-section]

const CASES = [
    [name device vendor level want];
    ["no card" null null null ""]
    ["amd card" 1 amd high "[gpu]\napply_gpu_optimisations=accept-responsibility\ngpu_device=1\namd_performance_level=high\n"]
    ["amd card, level unset" 0 amd null "[gpu]\napply_gpu_optimisations=accept-responsibility\ngpu_device=0\n"]
    ["nvidia card ignores the amd level" 0 nvidia high "[gpu]\napply_gpu_optimisations=accept-responsibility\ngpu_device=0\n"]
]

def main [] {
    let failed = $CASES | where {|c| (gpu-section $c.device $c.vendor $c.level) != $c.want }
    for c in $failed { print --stderr $"gamemode.test: ($c.name): got (gpu-section $c.device $c.vendor $c.level | to nuon)" }
    if ($failed | is-not-empty) { error make {msg: $"gamemode.test: ($failed | length) of ($CASES | length) cases failed"} }
}
