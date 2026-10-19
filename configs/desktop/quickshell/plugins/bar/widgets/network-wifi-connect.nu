#!/usr/bin/env -S nu --no-config-file --stdin
# the password comes as one stdin line, never argv (readable in /proc); empty falls back to secrets/wifi

const WIFI_TYPE = "802-11-wireless"

def profile-exists [ssid: string]: nothing -> bool {
    ^nmcli -g TYPE,NAME connection show
        | lines
        | where $it starts-with $"($WIFI_TYPE):"
        | each { str substring ($WIFI_TYPE | str length | $in + 1).. | str replace -a '\:' ':' }
        | any {|name| (^nmcli -g $"($WIFI_TYPE).ssid" connection show $name | str trim) == $ssid }
}

def main [ssid: string] {
    let typed = $in | default "" | lines | get 0? | default ""
    let secrets_wifi = [($env.QS_DOTFILES_DIR? | default $env.DOTFILES? | default ($env.HOME | path join projects/arch-dotfiles)) secrets/wifi] | path join
    let saved = if $typed == "" and ($secrets_wifi | path exists) and not (profile-exists $ssid) {
        try { open --raw $secrets_wifi | decode utf-8 | lines | parse "{ssid}\t{password}" | where ssid == $ssid and password != "" | get password.0? } catch { null }
    }
    let password = $saved | default $typed

    if $password == "" {
        ^nmcli dev wifi connect $ssid
    } else {
        $"($password)\n" | ^nmcli --ask dev wifi connect $ssid
    }

    # a saved network is home: reconnect with the hardware mac so the router's dhcp reservation holds
    if $saved != null {
        ^nmcli connection modify $ssid $"($WIFI_TYPE).cloned-mac-address" permanent
        ^nmcli connection up $ssid
    }
}
