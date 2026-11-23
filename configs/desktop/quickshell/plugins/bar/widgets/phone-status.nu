#!/usr/bin/env -S setpriv --pdeathsig TERM nu --no-config-file
# The paired, reachable phone as KDE Connect's daemon sees it, read from its session D-Bus API without starting it:
# one JSON record, `{available: false}` while no paired device is reachable or the daemon is down.

const SERVICE = "org.kde.kdeconnect"
const DAEMON_PATH = "/modules/kdeconnect"
const DAEMON_INTERFACE = "org.kde.kdeconnect.daemon"
const DEVICES_PATH = "/modules/kdeconnect/devices"
const DEVICE_INTERFACE = "org.kde.kdeconnect.device"
const PHONE_TYPE = "phone"
const UNAVAILABLE = {available: false}
# connectivity_report's strength while the phone has no cellular signal to report
const SIGNAL_NONE = -1
# the panel's actions, each the plugin it needs
const ACTION_PLUGINS = {
    ring: kdeconnect_findmyphone
    ping: kdeconnect_ping
    share: kdeconnect_share
    clipboard: kdeconnect_clipboard
    browse: kdeconnect_sftp
}

# busctl's short JSON lines, each one's data; a call's data is the list of its outputs. Empty when the call fails.
def busctl-data [...args: string]: nothing -> list<any> {
    let out = ^busctl --user --auto-start=no --json=short ...$args | complete
    if $out.exit_code != 0 { return [] }
    $out.stdout | lines | each { from json | get data }
}

def properties-get [path: string, interface: string, ...names: string]: nothing -> record {
    let values = busctl-data get-property $SERVICE $path $interface ...$names
    if ($values | length) != ($names | length) { return {} }
    $names | zip $values | into record
}

def method-call [path: string, interface: string, method: string, ...args: string]: nothing -> any {
    busctl-data call $SERVICE $path $interface $method ...$args | get 0?.0?
}

# The device the widget shows among the paired, reachable ones: the first phone, else the first device.
export def device-choose [devices: list<record>]: nothing -> any {
    $devices | where type == $PHONE_TYPE | append $devices | get 0?
}

# The widget's record from the device and its plugins' D-Bus properties; a plugin not loaded gives an empty record.
export def status-from [
    device: record<id: string, name: string, type: string>
    plugins: list<string>
    battery: record
    connectivity: record
    mounted: bool
]: nothing -> record {
    let has_battery = ($battery.hasBattery? | default false)
    let strength = ($connectivity.cellularNetworkStrength? | default $SIGNAL_NONE)
    {
        available: true
        id: $device.id
        name: $device.name
        type: $device.type
        battery: (if $has_battery { $battery.charge } else { null })
        charging: ($has_battery and ($battery.isCharging? | default false))
        signal: (if $strength > $SIGNAL_NONE { $strength } else { null })
        network: ($connectivity.cellularNetworkType? | default "")
        mounted: $mounted
        actions: ($ACTION_PLUGINS | transpose action plugin | each {|a| {$a.action: ($a.plugin in $plugins)} } | into record)
    }
}

def device-read [id: string]: nothing -> record {
    let path = $"($DEVICES_PATH)/($id)"
    {id: $id} | merge (properties-get $path $DEVICE_INTERFACE name type)
}

def main []: nothing -> nothing {
    let ids = method-call $DAEMON_PATH $DAEMON_INTERFACE devices bb "true" "true" | default []
    let device = device-choose ($ids | each { device-read $in } | where name? != null)
    if $device == null { print ($UNAVAILABLE | to json --raw); return }
    let path = $"($DEVICES_PATH)/($device.id)"
    let plugins = method-call $path $DEVICE_INTERFACE loadedPlugins | default []
    let battery = if "kdeconnect_battery" in $plugins {
        properties-get $"($path)/battery" $"($DEVICE_INTERFACE).battery" charge isCharging hasBattery
    } else { {} }
    let connectivity = if "kdeconnect_connectivity_report" in $plugins {
        properties-get $"($path)/connectivity_report" $"($DEVICE_INTERFACE).connectivity_report" cellularNetworkStrength cellularNetworkType
    } else { {} }
    let mounted = "kdeconnect_sftp" in $plugins and (method-call $"($path)/sftp" $"($DEVICE_INTERFACE).sftp" isMounted | default false)
    print (status-from $device $plugins $battery $connectivity $mounted | to json --raw)
}
