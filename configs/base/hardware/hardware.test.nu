#!/usr/bin/env -S nu --no-config-file
# nvidia-driver-for on one card of each generation, the Fermi and Tesla ids above the Kepler cutoff included.

use mod.nu [nvidia-driver-for]

const CASES = [
    [name id want];
    ["no nvidia card" 0x0000 none]
    ["Tesla GT200" 0x05e2 none]
    ["Fermi GF100" 0x06c0 none]
    ["Kepler GK104" 0x1180 470xx]
    ["Kepler GK208" 0x128b 470xx]
    ["Fermi GF119 above the cutoff" 0x104a none]
    ["Tesla GT218 above the cutoff" 0x10c3 none]
    ["Fermi GF117" 0x1140 none]
    ["Fermi GF114" 0x1201 none]
    ["Maxwell GM107" 0x1381 580xx]
    ["Volta GV100" 0x1db4 580xx]
    ["Turing TU102" 0x1e04 open]
    ["Ada AD102" 0x2684 open]
]

def main [] {
    let failed = $CASES | where {|c| (nvidia-driver-for $c.id) != $c.want }
    for c in $failed { print --stderr $"hardware.test: ($c.name): got (nvidia-driver-for $c.id)" }
    if ($failed | is-not-empty) { error make {msg: $"hardware.test: ($failed | length) of ($CASES | length) cases failed"} }
}
