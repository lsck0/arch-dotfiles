#!/usr/bin/env -S nu --no-config-file

const RESCAN_SETTLE = 1.5sec

def main [mode?: string] {
    if $mode == rescan {
        ^nmcli dev wifi rescan | complete
        sleep $RESCAN_SETTLE
    }
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
        } }
        | sort-by --reverse active signal
        | uniq-by ssid
        | to json -r
        | print
}
