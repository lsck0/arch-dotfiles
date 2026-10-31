#!/usr/bin/env -S nu --no-config-file
# Table cases for vm-scenario-plan (combining, presets, refusals), every scenario's snapshot edit still applying, the
# network a scenario plans (blocked cidrs, resolver, IPv6), what a teardown stops, a dry run writing nothing, and
# vm-verify on reported logs (finished, stopped after its disarm, planted failures, no way online).
use vm.nu [vm-scenario-plan vm-snapshot-edits vm-verify vm-homelab vm-network vm-network-command vm-processes vm-plan-lines]
use ../../platforms/homelab.nu [HOMELAB]

const REPO = path self ../..
const INVARIANTS = path self invariants.txt
const HOST = {lan: ["192.168.178.0/24"], lab: $HOMELAB.subnets, home_dns: $HOMELAB.router}
const STAGES_OK = "install: ok\nconfig: ok\n"
const STAGES_PLANTED = "install: failed, see install.log\nconfig: ok\n"
const STAGES_STOPPED = "install: failed, see install.log\ninstall: failed, see install.log\ninstall: failed, see install.log\n"

def fail [msg: string] { error make {msg: $"vm.test: ($msg)"} }

def plan [spec: string, platform: any, profile: any]: nothing -> any {
    try { vm-scenario-plan $spec $platform $profile } catch { null }
}

# A reported logs dir: every fixed invariant at its wanted value, then the case's facts, FAILURES files, stage log and
# status.
def logs-write [dir: path, facts: record, failures: record, stage: string, errors: int]: nothing -> nothing {
    rm --recursive --force $dir
    mkdir $dir
    let fixed = open --raw $INVARIANTS | lines | where {|l| $l != "" and not ($l | str starts-with "#") }
        | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+' | where want != "any"
        | reduce --fold {backup_roundtrip: ok, chain_stopped: no} {|i, acc| $acc | insert $i.key $i.want }
        | merge $facts
    $fixed | items {|k, v| $"($k)=($v)" } | str join "\n" | save ($dir | path join verify.log)
    $failures | items {|f, lines| $lines | str join "\n" | save ($dir | path join $f) } | ignore
    $stage | save ($dir | path join stage.log)
    {errors: $errors, last_run: test, checks: []} | to json | save ($dir | path join status.json)
}

def verify-cases []: nothing -> nothing {
    let dir = mktemp --directory
    let off_home = (vm-scenario-plan off-home null null).0
    let pkg_fail = (vm-scenario-plan pkg-fail null null).0
    let no_tor = (vm-scenario-plan no-tor null null).0
    let away = {home_network: no, mirror_reachable: yes}
    # a chain stopped offline before config, after install-stop's disarm: no next stage, the disk key and the
    # passwordless sudo gone, what config brings still missing
    let stopped = {
        home_network: no, mirror_reachable: no, issue_escape: yes, chain_stopped: yes, stage_armed: no
        sudo_passwordless: no, keyfile_present: no, luks_keyslots: 1, secure_boot: pending, setup_mode: pending
        pdf_queue: n/a, sshd_installed: no
    }
    let stopped_failures = {"FAILURES.install": ["system layer: pacman: failed retrieving file 'core.db' from archlinux.org"]}
    let planted = {home_network: yes, mirror_reachable: yes, planted_dropped: yes}
    let unresolvable = {"FAILURES.install": ["not on the mirror: lsck0-vm-test-unresolvable (a name new since the last nightly build arrives with the next one)"]}
    let no_tor_failures = {"FAILURES.install": ["not on the mirror: lsck0-vm-test-no-tor (a name new since the last nightly build arrives with the next one)"]}
    let cases = [
        [name run facts failures stage errors problems];
        [finished $off_home $away {} $STAGES_OK 0 0]
        [stopped $off_home $stopped $stopped_failures $STAGES_STOPPED 2 0]
        [stopped-still-armed $off_home ($stopped | merge {stage_armed: yes, sudo_passwordless: yes, keyfile_present: yes, luks_keyslots: 2}) $stopped_failures $STAGES_STOPPED 2 4]
        [stopped-unmarked $off_home ($stopped | merge {chain_stopped: no}) $stopped_failures $STAGES_STOPPED 2 8]
        [stopped-no-banner $off_home ($stopped | merge {issue_escape: no}) $stopped_failures $STAGES_STOPPED 2 2]
        [offline $off_home {home_network: no, mirror_reachable: no, issue_escape: no} {} $STAGES_OK 0 1]
        [errors $off_home $away {} $STAGES_OK 1 1]
        [at-home $off_home {home_network: yes, mirror_reachable: yes} {} $STAGES_OK 0 1]
        [no-config $off_home $away {} "install: ok\n" 0 1]
        [pkg-fail $pkg_fail $planted $unresolvable $STAGES_PLANTED 1 0]
        [pkg-fail-not-planted $pkg_fail ($planted | merge {planted_dropped: no}) {} "install: ok\nconfig: ok\n" 0 2]
        [pkg-fail-other-failure $pkg_fail $planted {"FAILURES.install": ($unresolvable."FAILURES.install" | append "base/sshd: unit sshd.service failed")} $STAGES_PLANTED 1 2]
        [pkg-fail-config-failed $pkg_fail $planted $unresolvable "install: failed, see install.log\nconfig: failed, see config.log\n" 1 1]
        [no-tor $no_tor ($planted | merge {tor_installed: no}) $no_tor_failures $STAGES_PLANTED 1 0]
        [no-tor-installed $no_tor ($planted | merge {tor_installed: yes}) $no_tor_failures $STAGES_PLANTED 1 1]
    ]
    for c in $cases {
        logs-write $dir $c.facts $c.failures $c.stage $c.errors
        let found = vm-verify $dir $c.run | get problems
        if ($found | length) != $c.problems { fail $"verify ($c.name): ($found | to nuon), wants ($c.problems) problems" }
    }
    rm --recursive --force $dir
}

# off-home and public-mirror plan the lab subnets of base/networkmanager's option, by default the lab's own, not a list
# of their own.
def network-cases []: nothing -> nothing {
    let lab = vm-homelab [luca-notebook]
    if $lab.subnets != $HOMELAB.subnets or $lab.dns != $HOMELAB.router { fail $"vm-homelab: ($lab | to nuon)" }
    if (vm-homelab [vm]).subnets != [] { fail "vm-homelab [vm]: the vm platform names no lab" }
    let cases = [
        [spec block dns forward ipv4_only];
        [home [] $HOMELAB.router true false]
        [off-home ($HOST.lan ++ $HOST.lab) "9.9.9.9" false true]
        [public-mirror $HOST.lab "9.9.9.9" false false]
        [notebook-2026-10-30 ($HOST.lan ++ $HOST.lab) "9.9.9.9" false true]
    ]
    for c in $cases {
        let net = vm-network (vm-scenario-plan $c.spec null null).0 $HOST | merge {host_port: 8765, socket: /s, pidfile: /p}
        let argv = vm-network-command $net
        let inner = $argv | last
        let got = {
            block: $net.block, dns: $net.dns, forward: ($inner | str contains $"--dns-host ($c.dns)")
            ipv4_only: ($inner | str contains " -4 ")
        }
        let want = {block: $c.block, dns: $c.dns, forward: $c.forward, ipv4_only: $c.ipv4_only}
        if $got != $want { fail $"network ($c.spec): ($got | to nuon), wants ($want | to nuon)" }
        for b in $c.block { if not ($inner | str contains $"unreachable ($b)") { fail $"network ($c.spec): ($b) not unreachable" } }
        if ($argv | first 2) != [nice -n] { fail $"network ($c.spec): pasta not at low priority: ($argv | to nuon)" }
        if ($inner | str contains " -P ") { fail $"network ($c.spec): passt writes a pidfile, it is pid 1 in pasta's namespace" }
    }
}

# Every process a run starts outside libvirt has a way to be stopped by name, under the vm's own cache dir.
def processes-cases []: nothing -> nothing {
    let name = "vm-test-unit"
    let dir = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join vm-test $name
    let procs = vm-processes $name
    if ($procs | get what | sort) != [passt pasta socat] { fail $"vm-processes: ($procs | get what | to nuon)" }
    for p in $procs {
        if not ($p.pattern | str contains $dir) { fail $"vm-processes ($p.what): ($p.pattern) is not this vm's" }
        if $p.pidfile != null and not ($p.pidfile | str starts-with $dir) { fail $"vm-processes ($p.what): ($p.pidfile)" }
    }
    if ($procs | where what in [socat pasta] | any { $in.pidfile == null }) { fail "socat and pasta need pidfiles" }
}

# A dry run plans every run and writes nothing, not even the vm's cache dir.
def dry-cases []: nothing -> nothing {
    let name = $"vm-test-dry-(random chars --length 8)"
    let dir = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join vm-test $name
    let lines = vm-scenario-plan "home,pkg-fail" null null | each { vm-plan-lines $in $name } | flatten
    if not ($lines | any { str contains "snapshot edits platforms/vm.nuon" }) { fail $"dry run: ($lines | to nuon)" }
    if ($dir | path exists) { rm --recursive --force $dir; fail $"dry run wrote ($dir)" }
}

def main [] {
    let cases = [
        [spec platform profile runs label run_platform run_profile blocks home_network];
        [home null null 1 home vm luca false true]
        [off-home null null 1 off-home vm luca true false]
        ["off-home,public-mirror" null custom 1 "off-home+public-mirror" vm custom true false]
        [notebook-2026-10-30 null null 1 notebook-2026-10-30 luca-notebook luca true false]
        [notebook-2026-10-30 vm null 1 notebook-2026-10-30 vm luca true false]
        ["pkg-fail,no-tor" null null 1 "pkg-fail+no-tor" vm luca false true]
        ["home,off-home" null null null null null null null null]
        [secrets-locked null custom null null null null null null]
        ["all,home" null null null null null null null null]
        [bogus null null null null null null null null]
        ["" null null null null null null null null]
    ]
    for c in $cases {
        let runs = plan $c.spec $c.platform $c.profile
        if $c.runs == null {
            if $runs != null { fail $"($c.spec | to nuon): planned, wants a refusal" }
            continue
        }
        if $runs == null or ($runs | length) != $c.runs { fail $"($c.spec | to nuon): ($runs | length) runs, wants ($c.runs)" }
        let r = $runs.0
        let got = [$r.label $r.platform $r.profile ($r.network.block | is-not-empty) $r.answers.home_network]
        let want = [$c.label $c.run_platform $c.run_profile $c.blocks $c.home_network]
        if $got != $want { fail $"($c.spec | to nuon): ($got | to nuon), wants ($want | to nuon)" }
    }
    let planted = (vm-scenario-plan "pkg-fail,no-tor" null null).0
    if $planted.stages != {install: failed} or ($planted.failures_allowed | length) != 3 { fail $"pkg-fail,no-tor: ($planted | select stages failures_allowed | to nuon)" }
    if (vm-scenario-plan home null null).0.stages != {} { fail "home expects stages other than ok" }

    let read = {|p| let f = $REPO | path join $p; if ($f | path exists) { open --raw $f } else { null } }
    let all = vm-scenario-plan all null null
    if ($all | where label == home | is-empty) { fail "all has no home run" }
    for r in $all {
        let edits = try { vm-snapshot-edits $r $read } catch {|e| fail $"($r.label): ($e.msg)" }
        let wanted = ($r.extra_packages | is-not-empty | into int) + ($r.replace | length)
        if ($edits | length) != $wanted { fail $"($r.label): ($edits | length) edits, wants ($wanted)" }
        for e in $edits {
            if $e.text == (do $read $e.path) { fail $"($r.label): ($e.path) unchanged" }
        }
    }
    verify-cases
    network-cases
    processes-cases
    dry-cases
    if (open --raw ($REPO | path join scripts lib vm.nu) | str contains "sudo") { fail "vm.nu calls sudo, dot test run runs as the user" }
}
