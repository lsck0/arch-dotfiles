#!/usr/bin/env -S nu --no-config-file
# End of a watched install chain: probes, dot status, backup roundtrip, logs uploaded, then the verdict beacon. Over
# http to the watcher and, when the vm has one, the virtio channel, which no guest firewall stands in front of.

use stage.nu [STAGE_STATE_DIR]
use homelab.nu [homelab-subnet-glob]
use ../../platforms/homelab.nu [HOMELAB]

const INVARIANTS = path self invariants.txt
const OUT = "/tmp/dotfiles-report"
const REPORT_ARCHIVE = $OUT + ".tgz"
const CHANNEL = "/dev/virtio-ports/lsck0.report"
# install-stop's own mark of a chain it stopped and disarmed; --stopped without it is no clean stop
const STOPPED_MARKER = $STAGE_STATE_DIR + "/stopped"
# who decides whether the guest gets out: tor's bootstrap, the router table, portmaster's verdicts, the resolver, the
# persona dispatcher that switches between them
const NETWORK_UNITS = [tor tor-router portmaster portmaster-bypass fw-egress systemd-resolved NetworkManager-dispatcher]

# --stopped: the chain stopped before config, so the verdict is chain-fail however the report itself went; the probes
# run after install-stop's disarm, so they prove it, and chain_stopped is yes only beside its marker
def main [user: string, checkout: path, --stopped]: nothing -> nothing {
    let url = open --raw ($STAGE_STATE_DIR | path join report) | str trim
    let ok = try { report $user $checkout $url $stopped; true } catch {|e| print --stderr $"stage-report: ($e.msg)"; false }
    let verdict = if $ok and not $stopped { 'chain-done' } else { 'chain-fail' }
    ^curl -s -m 10 $"($url)/beacon/($verdict)" | complete | ignore
    channel-send $verdict
}

# The archive as one base64 line, then the verdict; the watcher reads both off the channel's host file.
def channel-send [verdict: string]: nothing -> nothing {
    if not ($CHANNEL | path exists) { return }
    let archive = if ($REPORT_ARCHIVE | path exists) { open --raw $REPORT_ARCHIVE | encode base64 } else { "" }
    $"logs.tgz ($archive)\nbeacon ($verdict)\n" | ^tee $CHANNEL | complete | ignore
}

def report [user: string, checkout: path, url: string, stopped: bool]: nothing -> nothing {
    let luks = try { open --raw ($STAGE_STATE_DIR | path join luks-device) | str trim } catch { "" }
    rm --recursive --force $OUT
    mkdir $OUT
    # the lab's arch mirror's root, which answers only from the lab
    let lab_mirror = $HOMELAB.mirror.arch | url parse | select scheme host port | insert path "/" | url join
    let lsck0 = $HOMELAB.mirror.lsck0 | url parse
    let lsck0_mirror = $lsck0 | select scheme host port | insert path "/" | url join
    let lab_glob = $HOMELAB.subnets | each { homelab-subnet-glob $in } | str join "|"
    let probes = open --raw $INVARIANTS | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with "#") }
        | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+(?<where>\S+)\s+(?<probe>.*)$'
    # before portmaster goes: the mirror probe sees what the machine's own firewall lets out
    let facts = $probes | each {|i|
        let probe = $i.probe | str replace --all "@USER@" $user | str replace --all "@LUKS@" $luks | str replace --all "@CHECKOUT@" $checkout
            | str replace --all "@LAB_MIRROR@" $lab_mirror | str replace --all "@LSCK0_MIRROR@" $lsck0_mirror
            | str replace --all "@LSCK0_HOST@" $lsck0.host | str replace --all "@LAB_GLOB@" $lab_glob
        $"($i.key)=(^bash -c $probe | complete | get stdout | str trim)"
    }
    # what the network probes saw with portmaster up, then without it: tells portmaster apart from tor or the route
    let reach = "a=$(getent ahostsv4 archlinux.org | head -n 1); echo \"dns: ${a:-no answer}\"; curl -s -o /dev/null -m 20 -w 'https: %{http_code} %{errormsg}\n' https://archlinux.org"
    let with_portmaster = ^bash -c $reach | complete | get stdout
    # portmaster blocks the guest's requests to the watcher; only a watched install gets here
    do { ^systemctl stop portmaster.service } | complete | ignore
    # its stop hands resolved back its DoT with a restart that does not wait
    let without_portmaster = ^bash -c $"sleep 2; ($reach)" | complete | get stdout
    let as_user = {|command| ^runuser -l $user -c $'cd "$1" && ($command)' sh $checkout | complete }
    let status = do $as_user "nu --no-config-file scripts/dot.nu status --json"
    $status.stdout | save --force ($OUT | path join status.json)
    $status.stderr | save --force ($OUT | path join status.log)
    let roundtrip = do $as_user "nu --no-config-file scripts/dot.nu internal backup --roundtrip"
    $roundtrip.stdout + $roundtrip.stderr | save --force ($OUT | path join backup-roundtrip.log)
    $facts | append $"backup_roundtrip=(if $roundtrip.exit_code == 0 { 'ok' } else { 'fail' })"
        | append $"chain_stopped=(if $stopped and ($STOPPED_MARKER | path exists) { 'yes' } else { 'no' })" | str join "\n"
        | $"($in)\n" | save --force ($OUT | path join verify.log)
    cp ($STAGE_STATE_DIR | path join log) ($OUT | path join stage.log)
    ^journalctl -u dotfiles-stage.service --no-pager -o short-iso | save --force ($OUT | path join stage-journal.log)
    ^journalctl -b -p warning --no-pager -o short-iso | save --force ($OUT | path join config-boot-warnings.log)
    let reach_log = $"# reach with portmaster\n($with_portmaster)# reach without portmaster\n($without_portmaster)"
    ^bash -c "{ resolvectl status; cat /etc/resolv.conf; ip route; nft list ruleset; } 2>&1" | complete | get stdout
        | $"($reach_log)($in)" | save --force ($OUT | path join network.log)
    ^journalctl -b --no-pager -o short-iso ...($NETWORK_UNITS | each { [-u $in] } | flatten) | complete | get stdout
        | save --force ($OUT | path join network-journal.log)
    ^bash -c "cat /etc/issue.d/*.issue" | complete | get stdout | save --force ($OUT | path join issue.log)
    let logs = do { cd $checkout; glob "{FAILURES.*,**/*.log}" --exclude [**/.git/**] }
    for f in $logs {
        let dest = $OUT | path join ($f | path relative-to $checkout)
        mkdir ($dest | path dirname)
        cp $f $dest
    }
    ^tar -czf $REPORT_ARCHIVE -C $OUT .
    ^curl -s -m 120 -T $REPORT_ARCHIVE $"($url)/logs.tgz" | complete | ignore
}
