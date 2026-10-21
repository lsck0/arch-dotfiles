#!/usr/bin/nu --no-config-file

const REPORT = "/var/log/lynis-report.dat"
const WARNINGS_SHOWN = 5

def main []: nothing -> nothing {
    ^lynis audit system --cronjob --quiet | ignore
    let report = open --raw $REPORT | lines
    let index = $report | where ($it | str starts-with "hardening_index=") | str replace "hardening_index=" ""
        | str join
    let warnings = $report | where ($it | str starts-with "warning[]=") | str replace "warning[]=" ""
        | each { split row "|" | first 2 | str join " " }
    let shown = $warnings | first $WARNINGS_SHOWN | each { $"($in); " } | str join
        | if $in == "" { "" } else { $": ($in)" }
    let body = $"hardening index (if $index == '' { 'unknown' } else { $index }), ($warnings | length) warnings($shown)"
    ^logger -t dotfiles-health -p user.notice $"Lynis audit: ($body) \(lynis show details <test>\)"
}
