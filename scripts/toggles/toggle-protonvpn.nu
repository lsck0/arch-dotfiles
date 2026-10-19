#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run notify toggle-run]

const COUNTRY = "CH"

def tunnel-up []: nothing -> bool { "/sys/class/net/proton0" | path exists }

# portmaster comes back only if the firewall toggle wants it; polkit, so auto-vpn works unattended
def portmaster-restore []: nothing -> nothing {
    if (toggle-run firewall get | str trim) != permissive { ^systemctl --no-ask-password start portmaster.service }
}

def main [action: string = "toggle"] {
    switch-run {
        label: ProtonVPN
        is-on: {|| tunnel-up }
        on: {||
            # protonvpn's own networkmanager kill switch, routes only; set only while unset, which only the file shows
            let settings = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join Proton VPN settings.json
            if not (try { "killswitch" in (open $settings) } catch { false }) {
                ^protonvpn config set kill-switch standard | complete
            }
            # portmaster's connmark restore clobbers the wireguard fwmark; no admin to ask under auto-vpn, the dispatcher stops it
            ^systemctl --no-ask-password stop portmaster.service | complete
            let connect = ^protonvpn connect --country $COUNTRY | complete
            let output = $connect.stdout + $connect.stderr
            if $output =~ '(?i)authentication required' {
                notify ProtonVPN "Not signed in, run 'protonvpn signin' in a terminal first" --critical
            }
            if not (tunnel-up) {
                portmaster-restore
                error make {msg: $"connect failed: ($output)"}
            }
        }
        off: {||
            ^protonvpn disconnect o+e> /dev/null
            portmaster-restore
        }
    } $action
}
