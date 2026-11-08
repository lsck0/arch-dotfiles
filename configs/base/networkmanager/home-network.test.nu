#!/usr/bin/env -S nu --no-config-file
# home-network.nu's hardware mac check: a wifi whose mac NM randomised for a scan and set back to the hardware one is
# home (the kernel's addr_assign_type then reads 3), a random or set-over-zero mac never is; a nic with no stored
# permanent mac (virtio) is home only with the mac it came with (addr_assign_type 0). Then the tier a link reaches from
# the dispatcher's inputs: the two gateway files, `ip route`, the gateway's mac and NM's dhcp options.

const HOME_NETWORK = path self home-network.nu
use $HOME_NETWORK [hardware-mac-in-use gateways-parse route-gateway dhcp-server link-tier TIER_HOME TIER_TRUSTED TIER_NONE]

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

const ROUTER = "02:00:5e:10:00:01"
const ROGUE = "02:00:5e:10:00:99"
const FULL = "02:00:5e:10:00:01 192.0.2.1 192.0.2.1\n"
const ROUTE = "default via 192.0.2.1 dev wlan0 proto dhcp src 192.0.2.50 metric 600 \n"
const ROUTE_OTHER = "default via 198.51.100.1 dev wlan0 proto dhcp src 198.51.100.50 metric 600 \n"
const LEASE = "DHCP4.OPTION[1]:broadcast_address = 192.0.2.255\nDHCP4.OPTION[4]:dhcp_server_identifier = 192.0.2.1\n"
const LEASE_OTHER = "DHCP4.OPTION[4]:dhcp_server_identifier = 192.0.2.2\n"

const TIERS = [
    [name home trusted route gateway_mac dhcp4 tier];
    ["full line, all three match" $FULL "" $ROUTE $ROUTER $LEASE $TIER_HOME]
    ["upper case line, comments" $"# router\n\n($FULL | str uppercase)" "" $ROUTE $ROUTER $LEASE $TIER_HOME]
    ["cloned mac, other gateway address" $FULL "" $ROUTE_OTHER $ROUTER $LEASE $TIER_NONE]
    ["cloned mac and address, other dhcp server" $FULL "" $ROUTE $ROUTER $LEASE_OTHER $TIER_NONE]
    ["cloned mac and address, static address" $FULL "" $ROUTE $ROUTER "" $TIER_NONE]
    ["mac alone is trusted, not home" $"($ROUTER)\n" "" $ROUTE $ROUTER $LEASE $TIER_TRUSTED]
    ["mac alone beside a full line that fails" $"($ROUTER)\n($FULL)" "" $ROUTE_OTHER $ROUTER $LEASE $TIER_NONE]
    ["mac alone beside a full line that holds" $"($ROUTER)\n($FULL)" "" $ROUTE $ROUTER $LEASE $TIER_HOME]
    ["two fields is no line" "02:00:5e:10:00:01 192.0.2.1\n" "" $ROUTE $ROUTER $LEASE $TIER_NONE]
    ["trusted mac" "" $"($ROUTER)\n" $ROUTE $ROUTER "" $TIER_TRUSTED]
    ["trusted mac a failing home line names" $FULL $"($ROUTER)\n" $ROUTE_OTHER $ROUTER $LEASE $TIER_TRUSTED]
    ["unknown router" $FULL $"($ROUTER)\n" $ROUTE $ROGUE $LEASE $TIER_NONE]
    ["no default route" $FULL "" "" $ROUTER $LEASE $TIER_NONE]
    ["gateway never answered" $FULL "" $ROUTE "" $LEASE $TIER_NONE]
]

for c in $TIERS {
    let gateway = route-gateway $c.route
    let seen = if $gateway == null { null } else { {mac: $c.gateway_mac, gateway: $gateway, dhcp_server: (dhcp-server $c.dhcp4)} }
    let trusted = $c.trusted | lines | where $it != "" | str lowercase
    let got = link-tier (gateways-parse $c.home) $trusted $seen
    if $got != $c.tier { fail $"($c.name): ($got), want ($c.tier)" }
}
