#!/usr/bin/env -S nu --no-config-file
# wake.nu's pure parts by table: when the desktop is out of reach from here, and which router address sends the wake.

use std/assert
use scripts/wake.nu [reach-blocker router-address]

def main [] {
    let blockers = [
        [home wg dev blocked];
        [true false "" false]
        [false false "" true]
        [false true wg0 false]
        [false true wlan0 true]
    ]
    for c in $blockers { assert equal ((reach-blocker $c.home $c.wg $c.dev) != null) $c.blocked $"reach-blocker ($c | to nuon)" }
    let config = {router: "192.168.178.29", router_tunnel: "10.0.0.1"}
    let routers = [
        [config home dev want];
        [$config true "" "192.168.178.29"]
        [$config false wlan0 "10.0.0.1"]
        [($config | update router_tunnel null) false wg0 "192.168.178.29"]
        [($config | update router_tunnel null) false wlan0 null]
        [($config | update router null) true "" null]
    ]
    for c in $routers { assert equal (router-address $c.config $c.home $c.dev) $c.want $"router-address ($c | to nuon)" }
}
