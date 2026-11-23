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

# The uuid of the saved profile for ssid, null without one; by uuid, as a profile's name need not be its ssid.
def profile-uuid [ssid: string]: nothing -> any {
    ^nmcli -g TYPE,UUID connection show
        | lines
        | where $it starts-with $"($WIFI_TYPE):"
        | each { split row ":" | last }
        # unescaped (-g escapes ':' and '\'), and only the newline trimmed: an ssid may start or end with a space
        | where {|uuid| (^nmcli --escape no -g $"($WIFI_TYPE).ssid" connection show uuid $uuid | str trim --right --char "\n") == $ssid }
        | get 0?
}

# eduroam's common setup: peap with mschapv2 inside, the realm's radius certificate checked against the system cas so an
# evil twin cannot collect the password; the anonymous outer identity keeps the user name off the air
def connect-enterprise [ssid: string, identity: string, password: string]: nothing -> nothing {
    let realm = $identity | split row "@" | get --optional 1 | default ""
    if $realm == "" { error make {msg: $"wifi: ($ssid) wants an identity as user@realm"} }
    let eap = [
        wifi-sec.key-mgmt wpa-eap
        802-1x.eap peap 802-1x.phase2-auth mschapv2
        802-1x.identity $identity 802-1x.anonymous-identity $"anonymous@($realm)"
        802-1x.ca-cert $CA_BUNDLE 802-1x.domain-suffix-match $realm
        802-1x.password-flags 0
    ]
    # a saved profile takes the identity typed now: a corrected one (and its realm) would else be ignored
    let saved = profile-uuid $ssid
    let uuid = if $saved == null {
        # "Connection '<name>' (<uuid>) successfully added."
        ^nmcli connection add type wifi con-name $ssid ssid $ssid ...$eap
            | parse --regex '\((?<uuid>[0-9a-f-]{36})\)' | get --optional uuid.0
    } else {
        ^nmcli connection modify uuid $saved ...$eap
        $saved
    }
    if $uuid == null { error make {msg: $"wifi: no profile for ($ssid) after adding one"} }
    # nmcli answers NM's secret request from passwd-file on stdin; system-owned flags (0) make NM keep it like a psk
    $"802-1x.password:($password)\n" | ^nmcli connection up uuid $uuid passwd-file /dev/stdin
}

def main [ssid: string] {
    let input = $in | default "" | lines
    let typed = $input | get 0? | default ""
    let identity = $input | get 1? | default "" | str trim
    if $identity != "" { return (connect-enterprise $ssid $identity $typed) }

    let secrets_wifi = [($env.DOTFILES? | default ($nu.home-dir | path join projects arch-dotfiles)) configs/secrets/keys/wifi] | path join
    let saved = if $typed == "" and ($secrets_wifi | path exists) and (secret-is-plaintext $secrets_wifi) and (profile-uuid $ssid) == null {
        try { open --raw $secrets_wifi | decode utf-8 | lines | parse "{ssid}\t{password}" | where ssid == $ssid and password != "" | get password.0? } catch { null }
    }
    let password = $saved | default $typed

    if $password == "" {
        ^nmcli dev wifi connect $ssid
    } else {
        $"($password)\n" | ^nmcli --ask dev wifi connect $ssid
    }

    # a saved network is home: reconnect with the hardware mac so the router's dhcp reservation holds; by uuid, as the
    # name nmcli gave the new profile can clash with an older one's
    if $saved != null {
        let uuid = profile-uuid $ssid
        ^nmcli connection modify uuid $uuid $"($WIFI_TYPE).cloned-mac-address" permanent ipv6.method auto
        ^nmcli connection up uuid $uuid
    }
}
