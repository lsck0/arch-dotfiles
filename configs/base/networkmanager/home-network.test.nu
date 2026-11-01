#!/usr/bin/env -S nu --no-config-file
# home-network.nu's hardware mac check: a wifi whose mac NM randomised for a scan and set back to the hardware one is
# home (the kernel's addr_assign_type then reads 3), a random or set-over-zero mac never is.

const HOME_NETWORK = path self home-network.nu
use $HOME_NETWORK [hardware-mac-in-use]

def fail [msg: string] { error make {msg: $"home-network.test: ($msg)"} }

const CASES = [
    [name address ethtool home];
    ["hardware mac" "38:ba:f8:5a:51:40\n" "Permanent address: 38:ba:f8:5a:51:40\n" true]
    ["set back after a scan, upper case" "38:BA:F8:5A:51:40" "Permanent address: 38:ba:f8:5a:51:40" true]
    ["random mac of a foreign profile" "4e:75:58:a2:d5:40" "Permanent address: 38:ba:f8:5a:51:40" false]
    ["random-mac usb adapter" "4e:75:58:a2:d5:40" "Permanent address: 00:00:00:00:00:00" false]
    ["mac set over a zero one" "00:00:00:00:00:00" "Permanent address: 00:00:00:00:00:00" false]
    ["no ethtool" "38:ba:f8:5a:51:40" "" false]
    ["no address" "" "Permanent address: 38:ba:f8:5a:51:40" false]
]

for c in $CASES {
    let got = hardware-mac-in-use $c.address $c.ethtool
    if $got != $c.home { fail $"($c.name): ($got), want ($c.home)" }
}
