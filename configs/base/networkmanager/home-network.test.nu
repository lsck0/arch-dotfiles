#!/usr/bin/env -S nu --no-config-file
# home-network.nu's hardware mac check: a wifi whose mac NM randomised for a scan and set back to the hardware one is
# home (the kernel's addr_assign_type then reads 3), a random or set-over-zero mac never is; a nic with no stored
# permanent mac (virtio) is home only with the mac it came with (addr_assign_type 0). Then the tier a link reaches from
# the dispatcher's inputs: the two gateway files, `ip route`, the gateway's mac and NM's dhcp options, and the policy.

const HOME_NETWORK = path self home-network.nu
use $HOME_NETWORK [hardware-mac-in-use gateways-parse dhcp-server link-tier TIER_HOME TIER_TRUSTED TIER_NONE]
use std/assert
use lib/dispatch.nu [route-gateway]
use ini.nu [ini-rows]

const CASES = [
    [name address ethtool assign home];
    ["hardware mac" "02:00:5e:5a:51:40\n" "Permanent address: 02:00:5e:5a:51:40\n" "0\n" true]
    ["set back after a scan, upper case" "02:00:5E:5A:51:40" "Permanent address: 02:00:5e:5a:51:40" "3" true]
    ["random mac of a foreign profile" "4e:75:58:a2:d5:40" "Permanent address: 02:00:5e:5a:51:40" "3" false]
    ["random-mac usb adapter" "4e:75:58:a2:d5:40" "Permanent address: 00:00:00:00:00:00" "1" false]
    ["mac set over a zero one" "00:00:00:00:00:00" "Permanent address: 00:00:00:00:00:00" "3" false]
    ["virtio nic, its own mac, no stored one" "9a:55:9a:55:9a:55\n" "Permanent address: 00:00:00:00:00:00" "0\n" true]
    ["virtio nic, mac set by NM" "4e:75:58:a2:d5:40" "Permanent address: 00:00:00:00:00:00" "3" false]
    ["no ethtool, the device's own mac" "02:00:5e:5a:51:40" "" "0" true]
    ["no ethtool, a set mac" "02:00:5e:5a:51:40" "" "3" false]
    ["no address" "" "Permanent address: 02:00:5e:5a:51:40" "0" false]
]

for c in $CASES {
    let got = hardware-mac-in-use $c.address $c.ethtool $c.assign
    assert equal $got $c.home $"($c.name): ($got), want ($c.home)"
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

# untrusted_policy off: every routed link is trusted, whatever its gateway; home still wants its full line
const TRUST_ALL = [
    [name home trusted route gateway_mac dhcp4 tier];
    ["no gateway lists" "" "" $ROUTE "" "" $TIER_TRUSTED]
    ["no default route" "" "" "" "" "" $TIER_NONE]
    ["unknown router" $FULL "" $ROUTE $ROGUE $LEASE $TIER_TRUSTED]
    ["home line holds" $FULL "" $ROUTE $ROUTER $LEASE $TIER_HOME]
]

def tier-check [c: record, --trust-all]: nothing -> nothing {
    let gateway = route-gateway $c.route
    let seen = if $gateway == null { null } else { {mac: $c.gateway_mac, gateway: $gateway, dhcp_server: (dhcp-server $c.dhcp4)} }
    let trusted = $c.trusted | lines | where $it != "" | str lowercase
    let got = link-tier (gateways-parse ($c.home | lines)) $trusted $seen --trust-all=$trust_all
    assert equal $got $c.tier $"($c.name)(if $trust_all { ', policy off' }): ($got), want ($c.tier)"
}

for c in $TIERS { tier-check $c }
for c in $TRUST_ALL { tier-check $c --trust-all }

# A foreign network sees one MAC per network and boot, never the hardware one; only home_wired's drop-in keeps
# ethernet's, wifi never.
const NM_CONF = path self NetworkManager.conf
const HOME_WIRED = path self home-wired.conf
let conf = ini-rows (open --raw $NM_CONF) | where key != null
let mac = [
    [key want];
    ["connection.stable-id" "${CONNECTION}/${BOOT}"]
    ["wifi.cloned-mac-address" stable]
    ["ethernet.cloned-mac-address" stable]
]
for m in $mac {
    let got = $conf | where section == connection and key == $m.key | get --optional 0.value
    assert equal $got $m.want $"NetworkManager.conf: ($m.key) is ($got | to nuon), want ($m.want)"
}
let wired = ini-rows (open --raw $HOME_WIRED) | where key != null
let matches = $wired | where key == match-device | get value
assert (($wired | all { not ($in.key =~ '^wifi') }) and $matches == ["type:ethernet"]) "home-wired.conf reaches beyond ethernet"
