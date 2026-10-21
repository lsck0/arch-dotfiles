#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run toggle-run state-get state-set state-file notify]

const TUNNELS = [vpn protonvpn tor]
const NM_ONLINE_TIMEOUT_S = 30

def radios []: nothing -> table { ^rfkill -rno ID,SOFT | lines | parse "{id} {soft}" }

def offline []: nothing -> bool {
    (^nmcli networking | complete).stdout == "disabled\n" and (try { radios } catch { [] } | all { $in.soft != unblocked })
}

def main [action: string = "toggle"] {
    let saved_radios = state-file offline-rfkill --volatile
    switch-run {
        label: "Offline mode"
        is-on: {|| offline }
        on: {||
            let up = $TUNNELS | where {|name| (try { toggle-run $name get | str trim }) == on }
            for name in $up {
                try { toggle-run $name off } catch { print -e $"offline: failed to tear down ($name), continuing" }
            }
            if not (offline) {
                radios | where soft == unblocked | get id | str join "\n" | save --force $saved_radios
                state-set offline-tunnels ($up | str join " ") --volatile
            }
            ^nmcli networking off
            ^rfkill block all
        }
        off: {||
            let tunnels = state-get offline-tunnels --volatile | split row " "
            let back = {|name| $name not-in $tunnels or (try { toggle-run $name on o> /dev/null; true } catch { false }) }
            let ids = if ($saved_radios | path exists) { open --raw $saved_radios | lines } else { [all] }
            if ($ids | is-not-empty) { ^rfkill unblock ...$ids }
            mut failed = []
            if not (do $back tor) { $failed ++= [tor] }
            ^nmcli networking on
            if not (do $back vpn) { $failed ++= [vpn] }
            if protonvpn in $tunnels and not ((^nm-online -qt $NM_ONLINE_TIMEOUT_S | complete).exit_code == 0 and (do $back protonvpn)) {
                $failed ++= [protonvpn]
            }
            rm --force $saved_radios (state-file offline-tunnels --volatile)
            if ($failed | is-not-empty) {
                notify "Offline mode" $"Back online, but ($failed | str join ', ') did not come back: traffic is not tunnelled" --critical
            }
        }
    } $action
}
