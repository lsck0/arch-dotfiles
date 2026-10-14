#!/usr/bin/env -S nu --no-config-file
# desktop notifications from the system journal: failed system units (user units have OnFailure=), smartd's disk
# warnings, and root's reports under the identifier dotfiles-health (lynis-audit). wheel reads the whole journal, a
# login outside it sees none of these entries and gets nothing

# a unit failing over and over (an unreachable mount) shows at most hourly, replacing its own card
const COOLDOWN = 1hr
const PRIORITY_ERR = 3
# trusted fields only, journald sets _PID and _UID: unit failures from pid 1, smartd at crit and worse, reports
const MATCHES = [
    _PID=1 MESSAGE_ID=d9b373ed55a64feb8242e02dbe79a49c
    + _UID=0 SYSLOG_IDENTIFIER=smartd PRIORITY=0 PRIORITY=1 PRIORITY=2
    + _UID=0 SYSLOG_IDENTIFIER=dotfiles-health
]

def card [entry: record]: nothing -> any {
    let message = $entry.MESSAGE? | if ($in | describe) == string { $in } else { "" }
    match ($entry.SYSLOG_IDENTIFIER? | default "-") {
        smartd => {key: smartd, urgency: critical, title: "Disk health", body: $message}
        dotfiles-health => {
            # "<title>: <body>", err and worse is critical
            let title = $message | split row ": " | first
            let critical = ($entry.PRIORITY? | default "6" | into int) <= $PRIORITY_ERR
            {key: $title, urgency: (if $critical { "critical" } else { "normal" }), title: $title
                body: ($message | str replace --regex '^.*?: ' '')}
        }
        _ => {
            let unit = $entry.UNIT? | default "-"
            # one that restarts on failure is not failed yet
            if (^systemctl -q is-failed $unit | complete).exit_code != 0 { return null }
            {key: $unit, urgency: critical, title: $"($unit) failed", body: $"journalctl -xeu ($unit)"}
        }
    }
}

def main []: nothing -> nothing {
    mut shown = {}
    for line in (^journalctl --no-pager -f -n 0 -o json ...$MATCHES | lines) {
        let c = card ($line | from json)
        let prev = if $c == null { null } else { $shown | get --optional $c.key }
        if $c == null or ($prev != null and (date now) - $prev.at < $COOLDOWN) { continue }
        let replace = if $prev.id? == null { [] } else { [-r $prev.id] }
        let sent = ^notify-send -p -a system -u $c.urgency ...$replace $c.title $c.body | complete
        let id = if $sent.exit_code == 0 { $sent.stdout | str trim } else { $prev.id? }
        $shown = $shown | upsert $c.key {at: (date now), id: $id}
    }
    # the follow ending is a failure, so Restart= brings it back
    print --stderr "journalctl -f ended"
    exit 1
}
