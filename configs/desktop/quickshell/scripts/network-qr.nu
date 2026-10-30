#!/usr/bin/env -S nu --no-config-file
# the active wifi as a WIFI: qr matrix, one "0"/"1" row per line; --meta first adds "meta\t<iface>\t<security>\t<ssid>"

const PROBE = "1.1.1.1"
const FIELDS = "802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless.hidden,802-11-wireless-security.wep-key0"

def fail [message: string] {
    print -e $message
    exit 1
}

def qr-escape []: string -> string {
    str replace -a '\' '\\' | str replace -a ';' '\;' | str replace -a ',' '\,' | str replace -a ':' '\:' | str replace -a '"' '\"'
}

def main [interface?: string, --meta] {
    let interface = if $interface != null { $interface } else {
        let route_device = ^ip -j route get $PROBE | complete | get stdout | from json | get 0?.dev?
        if $route_device != null and ($"/sys/class/net/($route_device)/wireless" | path exists) {
            $route_device
        } else {
            ^nmcli -t -f DEVICE,TYPE,STATE device status | lines | parse "{device}:{type}:{state}"
                | where type == wifi and ($it.state | str starts-with connected) | get 0?.device
        }
    }
    if $interface == null { fail "No active Wi-Fi connection" }
    let device = ^nmcli --get-values GENERAL.CON-UUID device show $interface
    let uuid = $device | lines | get 0?
    if $uuid in [null "" "--"] { fail "No active Wi-Fi connection" }

    let fields = ^nmcli --show-secrets --escape no --get-values $FIELDS connection show uuid $uuid | lines
    let ssid = $fields.0? | default ""
    let key_management = $fields.1? | default ""
    let psk = $fields.2? | default ""
    let wep_key = $fields.4? | default ""

    if $ssid == "" { fail "Could not read the Wi-Fi name" }
    if ($key_management =~ "eap|ieee8021x") { fail "Enterprise Wi-Fi cannot be shared with a password QR code" }
    let security = if $key_management not-in ["" "none"] { "WPA" } else if $wep_key != "" { "WEP" } else { "nopass" }
    let password = match $security { WPA => $psk, WEP => $wep_key, _ => "" }
    if $security == "WPA" and $password == "" { fail "Could not read the Wi-Fi password" }
    let hidden = if ($fields.3? | default no) == "yes" { "H:true;" } else { "" }

    if $meta { print $"meta\t($interface)\t($security)\t($ssid)" }
    # stdin, never an argv visible in /proc
    $"WIFI:T:($security);S:($ssid | qr-escape);P:($password | qr-escape);($hidden);"
        | ^qrencode --type ASCII --margin 4 --output -
        | lines
        | each { split chars | chunks 2 | each { if "#" in $in { "1" } else { "0" } } | str join }
        | to text
        | print -n
}
