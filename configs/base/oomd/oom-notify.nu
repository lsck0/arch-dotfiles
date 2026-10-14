#!/usr/bin/env -S nu --no-config-file
# only the managers write these ids: pid 1 for system units, this user's manager (USER_UNIT=) for app.slice; _PID is
# set by journald, so a logger --journald from any local user cannot fake a kill

# systemd.catalog's ids
const OOMD_KILL_ID = "d989611b15e44c9dbf31e3c81256e4ed"
const KERNEL_KILL_ID = "fe6faa94e7774663a0da52717891d8ef"

def main []: nothing -> nothing {
    let manager = $env.MANAGERPID? | default ""
    if $manager == "" {
        print --stderr "oom-notify runs as a user unit"
        exit 1
    }
    let manager_unit = $"user@(^id -u | str trim).service"
    let matches = [$"MESSAGE_ID=($OOMD_KILL_ID)" $"MESSAGE_ID=($KERNEL_KILL_ID)" _PID=1 $"_PID=($manager)"]
    for line in (^journalctl --no-pager -f -n 0 -o json ...$matches | lines) {
        let entry = $line | from json
        let unit = $entry.USER_UNIT? | default $entry.UNIT? | default "unknown unit"
        # pid 1 also reports the kill on user@UID.service, and a kernel kill is repeated on every ancestor slice
        # (-.slice, app.slice); slices hold no processes, so only the leaf service/scope names the kill
        if $unit == $manager_unit or ($unit | str ends-with ".slice") { continue }
        let source = if $entry.MESSAGE_ID? == $OOMD_KILL_ID { "systemd-oomd, memory pressure" } else {
            "kernel OOM killer, last resort"
        }
        let message = $entry.MESSAGE? | if ($in | describe) == string { $in } else { "OOM kill event" }
        ^notify-send -u critical -a "OOM Killer" -- $"Killed: ($unit)" $"($message) \(($source)\)"
    }
}
