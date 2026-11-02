#!/usr/bin/env -S nu --no-config-file
# home-network.nu's hardware mac check: a wifi whose mac NM randomised for a scan and set back to the hardware one is
# home (the kernel's addr_assign_type then reads 3), a random or set-over-zero mac never is; a nic with no stored
# permanent mac (virtio) is home only with the mac it came with (addr_assign_type 0).

const HOME_NETWORK = path self home-network.nu
use $HOME_NETWORK [hardware-mac-in-use]

def fail [msg: string] { error make {msg: $"home-network.test: ($msg)"} }

const CASES = [
    [name address ethtool assign home];
    ["hardware mac" "38:ba:f8:5a:51:40\n" "Permanent address: 38:ba:f8:5a:51:40\n" "0\n" true]
    ["set back after a scan, upper case" "38:BA:F8:5A:51:40" "Permanent address: 38:ba:f8:5a:51:40" "3" true]
    ["random mac of a foreign profile" "4e:75:58:a2:d5:40" "Permanent address: 38:ba:f8:5a:51:40" "3" false]
    ["random-mac usb adapter" "4e:75:58:a2:d5:40" "Permanent address: 00:00:00:00:00:00" "1" false]
    ["mac set over a zero one" "00:00:00:00:00:00" "Permanent address: 00:00:00:00:00:00" "3" false]
    ["virtio nic, its own mac, no stored one" "9a:55:9a:55:9a:55\n" "Permanent address: 00:00:00:00:00:00" "0\n" true]
    ["virtio nic, mac set by NM" "4e:75:58:a2:d5:40" "Permanent address: 00:00:00:00:00:00" "3" false]
    ["no ethtool, the device's own mac" "38:ba:f8:5a:51:40" "" "0" true]
    ["no ethtool, a set mac" "38:ba:f8:5a:51:40" "" "3" false]
    ["no address" "" "Permanent address: 38:ba:f8:5a:51:40" "0" false]
]

for c in $CASES {
    let got = hardware-mac-in-use $c.address $c.ethtool $c.assign
    if $got != $c.home { fail $"($c.name): ($got), want ($c.home)" }
}
