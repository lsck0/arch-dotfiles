#!/usr/bin/env -S setpriv --pdeathsig TERM nu --no-config-file

const ALERTS_DIR = "/var/lib/ossec-hids/logs/alerts"
const ALERTS_LOG = "/var/lib/ossec-hids/logs/alerts/alerts.log"
const OSSEC_TARGET = "ossec-server.target"
const WINDOW = 24hr
# ossec levels: 7 fires on every syscheck change after an upgrade, 10+ is repeated failures or high importance
const LEVEL_HIGH = 10
const RECENT_COUNT = 3
const DEBOUNCE = 500ms
const ALERT_MARK = "** Alert "
const MAIN_JOB = 0

# Whole alerts only, each blank-line terminated: "** Alert <ts>.<id>: ..." then "Rule: <id> (level <n>) -> '<desc>'".
def alerts-parse [text: string]: nothing -> table {
    $text | split row $ALERT_MARK | skip 1 | each {|block|
        let rule = $block | parse -r '(?m)^Rule: (?<rule>.*?) \(level (?<level>\d+)\) -> (?<desc>.*)$' | get 0?
        let ts = $block | parse -r '^(?<ts>\d+)\.' | get 0?.ts
        if $rule != null and $ts != null {
            let desc = $rule.desc | str trim -c "'"
            {ts: ($ts | into int), level: ($rule.level | into int), rule: $rule.rule, desc: $desc}
        }
    }
}

def main [] {
    if (^systemctl is-active --quiet $OSSEC_TARGET | complete).exit_code != 0 { return }
    job spawn { watch $ALERTS_DIR --quiet --recursive false --debounce $DEBOUNCE | each { job send $MAIN_JOB } }
    mut tail = {inode: 0, offset: 0, pending: ""}
    mut alerts = []
    mut last = ""
    loop {
        if ($ALERTS_LOG | path exists) {
            let stat = ^stat -c '%i %s' $ALERTS_LOG | split row " " | into int
            if $stat.0 != $tail.inode or $stat.1 < $tail.offset { $tail = {inode: $stat.0, offset: 0, pending: ""} }
            let data = ^tail -c $"+($tail.offset + 1)" $ALERTS_LOG | into binary
            let text = $tail.pending + ($data | decode utf-8)
            let end = $text | str index-of -e "\n\n"
            let cut = if $end < 0 { 0 } else { $end + 2 }
            let offset = $tail.offset + ($data | bytes length)
            $tail = {inode: $stat.0, offset: $offset, pending: ($text | str substring $cut..)}
            $alerts = $alerts | append (alerts-parse ($text | str substring ..<$cut))
        }
        let now_s = (date now | into int) // 1_000_000_000
        let window_s = $WINDOW // 1sec
        $alerts = $alerts | where ts >= $now_s - $window_s
        let line = {
            total: ($alerts | length)
            high: ($alerts | where level >= $LEVEL_HIGH | length)
            maxLevel: ($alerts | get level | append 0 | math max)
            recent: ($alerts | last $RECENT_COUNT | reverse | each {|a|
                {t: ($a.ts * 1_000_000_000 | into datetime | date to-timezone local | format date "%H:%M")}
                | merge ($a | reject ts)
            })
        } | to json -r
        if $line != $last {
            print $line
            $last = $line
        }
        let expiry = if ($alerts | is-empty) { null } else { ($alerts.0.ts + $window_s - $now_s + 1) * 1sec }
        try { if $expiry == null { job recv } else { job recv --timeout $expiry } }
    }
}
