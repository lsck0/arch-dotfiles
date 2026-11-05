#!/usr/bin/env -S nu --no-config-file --stdin
# the password comes as stdin line one, never argv (readable in /proc); empty falls back to configs/secrets/keys/wifi.
# Line two, the identity (user@realm), marks a wpa-eap network such as eduroam: `nmcli dev wifi connect` only knows
# psk, so that one gets its own profile

const WIFI_TYPE = "802-11-wireless"
const GITCRYPT_MAGIC = 0x[00 47 49 54 43 52 59 50 54]
const CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"

# A locked git-crypt secret opens as its \0GITCRYPT header; never parse one as a password file.
def secret-is-plaintext [file: path]: nothing -> bool {
    (open --raw $file | first ($GITCRYPT_MAGIC | bytes length) | into binary) != $GITCRYPT_MAGIC
}

def profile-exists [ssid: string]: nothing -> bool {
    ^nmcli -g TYPE,NAME connection show
        | lines
        | where $it starts-with $"($WIFI_TYPE):"
        | each { str substring ($WIFI_TYPE | str length | $in + 1).. | str replace -a '\:' ':' }
        | any {|name| (^nmcli -g $"($WIFI_TYPE).ssid" connection show $name | str trim) == $ssid }
}

# eduroam's common setup: peap with mschapv2 inside, the realm's radius certificate checked against the system cas so an
# evil twin cannot collect the password; the anonymous outer identity keeps the user name off the air
def connect-enterprise [ssid: string, identity: string, password: string]: nothing -> nothing {
    let realm = $identity | split row "@" | get --optional 1 | default ""
    if $realm == "" { error make {msg: $"wifi: ($ssid) wants an identity as user@realm"} }
    if not (profile-exists $ssid) {
        (
            ^nmcli connection add type wifi con-name $ssid ssid $ssid
                wifi-sec.key-mgmt wpa-eap
                802-1x.eap peap 802-1x.phase2-auth mschapv2
                802-1x.identity $identity 802-1x.anonymous-identity $"anonymous@($realm)"
                802-1x.ca-cert $CA_BUNDLE 802-1x.domain-suffix-match $realm
                802-1x.password-flags 0
        )
    }
    # nmcli answers NM's secret request from passwd-file on stdin; system-owned flags (0) make NM keep it like a psk
    $"802-1x.password:($password)\n" | ^nmcli connection up id $ssid passwd-file /dev/stdin
}

def main [ssid: string] {
    let input = $in | default "" | lines
    let typed = $input | get 0? | default ""
    let identity = $input | get 1? | default "" | str trim
    if $identity != "" { return (connect-enterprise $ssid $identity $typed) }

    let secrets_wifi = [($env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles)) configs/secrets/keys/wifi] | path join
    let saved = if $typed == "" and ($secrets_wifi | path exists) and (secret-is-plaintext $secrets_wifi) and not (profile-exists $ssid) {
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
        ^nmcli connection modify $ssid $"($WIFI_TYPE).cloned-mac-address" permanent ipv6.method auto
        ^nmcli connection up $ssid
    }
}
