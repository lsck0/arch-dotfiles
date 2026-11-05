#!/usr/bin/env -S nu --no-config-file

const RESCAN_SETTLE = 1.5sec

# The ssids NM has a profile for: those connect with the saved secret, no password asked.
def known-ssids []: nothing -> list<string> {
    ^nmcli -t -f TYPE,UUID connection show | lines | where $it starts-with "802-11-wireless:"
    | each { split row ":" | last } | each {|uuid| ^nmcli -g 802-11-wireless.ssid connection show $uuid | str trim }
}

def main [mode?: string] {
    if $mode == rescan {
        ^nmcli dev wifi rescan | complete
        sleep $RESCAN_SETTLE
    }
    let known = known-ssids
    # ssid last and unescaped, so colons in it stay part of it
    ^nmcli -t -e no -f ACTIVE,SIGNAL,SECURITY,SSID dev wifi list
        | lines
        | parse -r '^(?<active>[^:]*):(?<signal>[^:]*):(?<security>[^:]*):(?<ssid>.*)$'
        | where ssid != ""
        | each {|n| {
            active: ($n.active == yes)
            ssid: $n.ssid
            signal: ($n.signal | into int)
            secure: ($n.security not-in ["" "--"])
            # wpa-eap (eduroam): asks for an identity next to the password
            enterprise: ($n.security =~ "802\\.1X")
            known: ($n.ssid in $known)
        } }
        | sort-by --reverse active signal
        | uniq-by ssid
        | to json -r
        | print
}
