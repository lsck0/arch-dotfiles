#!/usr/bin/nu --no-config-file

const REPORT = "/var/log/lynis-report.dat"
const WARNINGS_SHOWN = 5

def main []: nothing -> nothing {
    ^lynis audit system --cronjob --quiet | ignore
    let report = open --raw $REPORT | lines
    let index = $report | where ($it | str starts-with "hardening_index=") | str replace "hardening_index=" ""
        | get --optional 0 | default unknown
    let warnings = $report | where ($it | str starts-with "warning[]=") | str replace "warning[]=" ""
        | each { split row "|" | first 2 | str join " " }
    let shown = if ($warnings | is-empty) { "" } else { $": ($warnings | first $WARNINGS_SHOWN | str join '; ')" }
    let body = $"hardening index ($index), ($warnings | length) warnings($shown)"
    ^logger -t dotfiles-health -p user.notice $"Lynis audit: ($body) \(lynis show details <test>\)"
}
