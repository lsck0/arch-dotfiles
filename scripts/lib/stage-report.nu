#!/usr/bin/env -S nu --no-config-file
# The end of a watched install chain (dot test): root runs the invariant probes and the backup roundtrip on the
# disarmed system, packs the logs and hands them to the watcher, then beacons chain-done, or chain-fail when any
# of it failed, so the watcher never waits out its timeout. stage.nu runs it last.

const STATE_DIR = "/var/lib/dotfiles-stage"
const INVARIANTS = path self invariants.txt
const OUT = "/tmp/dotfiles-report"

def main [user: string, checkout: path]: nothing -> nothing {
    let url = open --raw ($STATE_DIR | path join report) | str trim
    # portmaster blocks the guest's requests to the watcher; only a watched install gets here
    do { ^systemctl stop portmaster.service } | complete | ignore
    let ok = try { report $user $checkout $url; true } catch {|e| print --stderr $"stage-report: ($e.msg)"; false }
    ^curl -s -m 10 $"($url)/beacon/(if $ok { 'chain-done' } else { 'chain-fail' })" | complete | ignore
}

def report [user: string, checkout: path, url: string]: nothing -> nothing {
    let luks = try { open --raw ($STATE_DIR | path join luks-device) | str trim } catch { "" }
    rm --recursive --force $OUT
    mkdir $OUT
    let probes = open --raw $INVARIANTS | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with "#") }
        | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+(?<where>\S+)\s+(?<probe>.*)$'
    let facts = $probes | each {|i|
        let probe = $i.probe | str replace --all "@USER@" $user | str replace --all "@LUKS@" $luks
        $"($i.key)=(^bash -c $probe | complete | get stdout | str trim)"
    }
    let roundtrip = ^runuser -l $user -c $"cd ($checkout) && nu --no-config-file scripts/dot.nu internal backup --roundtrip" | complete
    $roundtrip.stdout + $roundtrip.stderr | save --force ($OUT | path join backup-roundtrip.log)
    $facts | append $"backup_roundtrip=(if $roundtrip.exit_code == 0 { 'ok' } else { 'fail' })" | str join "\n"
        | $"($in)\n" | save --force ($OUT | path join verify.log)
    cp ($STATE_DIR | path join log) ($OUT | path join stage.log)
    ^journalctl -u dotfiles-stage.service --no-pager -o short-iso | save --force ($OUT | path join stage-journal.log)
    ^journalctl -b -p warning --no-pager -o short-iso | save --force ($OUT | path join config-boot-warnings.log)
    ^bash -c "{ resolvectl status; cat /etc/resolv.conf; } 2>&1" | save --force ($OUT | path join network.log)
    let logs = glob ($checkout | path join "{FAILURES.*,*.log,**/*.log}") --exclude [**/.git/**]
    for f in $logs { cp $f $OUT }
    ^tar -czf /tmp/dotfiles-report.tgz -C $OUT .
    ^curl -s -m 120 -T /tmp/dotfiles-report.tgz $"($url)/logs.tgz" | complete | ignore
}
