#!/usr/bin/env -S nu --no-config-file
# The agent package stays at the lab manager's version (an agent never runs newer than its manager), and the secret the
# lab names is the one meta.secrets hands root.

use std/assert
use ../../../platforms/homelab.nu [HOMELAB]
use mod.nu [meta]

const PKGBUILD = path self ../../../mirror/pkgbuilds/wazuh-agent/PKGBUILD

def main [] {
    if $HOMELAB.wazuh == null { return }
    let pkgver = open --raw $PKGBUILD | parse --regex '(?m)^pkgver=(?<v>\S+)$' | get 0.v
    assert equal $pkgver $HOMELAB.wazuh.version $"wazuh-agent ($pkgver), the lab's manager ($HOMELAB.wazuh.version)"
    assert ($HOMELAB.wazuh.secret in $meta.secrets) $"meta.secrets lacks the lab's ($HOMELAB.wazuh.secret)"
}
