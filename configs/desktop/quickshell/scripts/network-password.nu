#!/usr/bin/env -S nu --no-config-file
# the password of the wifi on <interface>, on stdout only, never an argv visible in /proc

const FIELDS = "802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless-security.wep-key0"

def fail [message: string] {
    print -e $message
    exit 1
}

def main [interface: string] {
    let device = ^nmcli --get-values GENERAL.CON-UUID device show $interface
    let uuid = $device | lines | get 0?
    if $uuid in [null "" "--"] { fail "No active Wi-Fi connection" }

    let fields = ^nmcli --show-secrets --escape no --get-values $FIELDS connection show uuid $uuid | lines
    let key_management = $fields.0? | default ""
    if ($key_management =~ "eap|ieee8021x") { fail "Enterprise Wi-Fi has no shareable password" }
    let wep = $key_management in ["" "none"]
    let password = $fields | get -o (if $wep { 2 } else { 1 }) | default ""
    if $password == "" { fail (if $wep { "This network has no password" } else { "Could not read the Wi-Fi password" }) }
    print $password
}
