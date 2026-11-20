#!/usr/bin/env -S nu --no-config-file
# The worker's protocol by table: the original command's strict parse, the job spec's checks (kinds, ids, pinned
# images, nix refused, paths inside the checkout, the network and the caps), the idle gate, the consent decision and
# the login's half of it, the offer, the manifest and the metrics state; then admission and serve against a scratch
# OFFLOAD_ROOT, serve refusing anything but its vocabulary.

use worker.nu [
    command-parse spec-validate toolchain-validate path-inside-valid power-on-battery gate-reasons consent-decide
    manifest-build metrics-state offer-build job-state admit CONSENT_WINDOW KIND_TIMEOUT_S
]
use consent.nu [request-pending action-answer]
use std/assert

const SCRIPT = path self worker.nu
const COMMIT = "0123456789abcdef0123456789abcdef01234567"
const IMAGE = "ghcr.io/lsck0/site-builder:1.2@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const LIMITS = {memoryMiB: 16384, cpus: 8}
const SPEC = {
    kind: static-site, repo: "lsck0/site", commit: $COMMIT, toolchain: {oci: $IMAGE}
    command: [zola build --output-dir public], workdir: ".", output: public, network: false
    memoryMiB: 4096, cpus: 4, timeoutS: 1800
}

def refused [what: string, thunk: closure]: nothing -> nothing {
    assert not (try { do $thunk; true } catch { false }) $"($what) passed"
}

def parse-cases [] {
    assert equal (command-parse offer) {verb: offer, arg: ""}
    assert equal (command-parse "status lab-builder-20261120-101010-ab12") {verb: status, arg: "lab-builder-20261120-101010-ab12"}
    assert equal (command-parse 'submit {"a": "b c"}') {verb: submit, arg: '{"a": "b c"}'}
    let bad = [
        "" "sh -c id" "offer now" "gc x" "status" "status ../etc" "status a;b" "get A" "cancel x y" "submit"
        " offer" "OFFER" "offer\nsubmit" "status lab\n" "rm -rf /" ("submit " + (1..70000 | each { "x" } | str join))
    ]
    for b in $bad { refused $"parse ($b | str substring 0..<40 | to nuon)" { command-parse $b } }
}

def spec-cases [] {
    assert equal (spec-validate $SPEC $LIMITS) $SPEC "spec: the valid job"
    assert equal (spec-validate ($SPEC | update kind arch-base | update network true) $LIMITS).network true "spec: arch-base network"
    assert equal (spec-validate ($SPEC | update cpus 1.5) $LIMITS).cpus 1.5 "spec: fractional cpus"
    let bad = [
        [name spec];
        [not-a-record [1 2]]
        [missing ($SPEC | reject output)]
        [unknown ($SPEC | insert shell true)]
        [kind ($SPEC | update kind run)]
        [kind-type ($SPEC | update kind 1)]
        [repo-dots ($SPEC | update repo "../x")]
        [repo-space ($SPEC | update repo "a b")]
        [short-commit ($SPEC | update commit "0123456")]
        [upper-commit ($SPEC | update commit ($COMMIT | str uppercase))]
        [sha256-commit ($SPEC | update commit ($COMMIT + "000000000000000000000000"))]
        [tag-only ($SPEC | update toolchain {oci: "ghcr.io/lsck0/site-builder:1.2"})]
        [unqualified ($SPEC | update toolchain {oci: ("site@sha256:" + (1..64 | each { "a" } | str join))})]
        [short-digest ($SPEC | update toolchain {oci: "ghcr.io/x/y@sha256:abc"})]
        [nix ($SPEC | update toolchain {nix: "/nix/store/abc-gcc", drv: "/nix/store/abc.drv"})]
        [two-toolchains ($SPEC | update toolchain {oci: $IMAGE, nix: "/nix/store/x"})]
        [empty-command ($SPEC | update command [])]
        [string-command ($SPEC | update command "zola build")]
        [number-arg ($SPEC | update command [zola 1])]
        [nul-arg ($SPEC | update command [$"a(char nul)b"])]
        [long-command ($SPEC | update command (1..257 | each { "x" }))]
        [absolute-workdir ($SPEC | update workdir "/etc")]
        [escaping-output ($SPEC | update output "public/../../x")]
        [empty-output ($SPEC | update output "")]
        [network ($SPEC | update network true)]
        [network-type ($SPEC | update network "no")]
        [memory-over ($SPEC | update memoryMiB 20000)]
        [memory-under ($SPEC | update memoryMiB 16)]
        [memory-float ($SPEC | update memoryMiB 4096.5)]
        [cpus-zero ($SPEC | update cpus 0)]
        [cpus-over ($SPEC | update cpus 9)]
        [timeout-over ($SPEC | update timeoutS 7201)]
        [timeout-oci-image ($SPEC | update kind oci-image | update timeoutS 3601)]
        [timeout-zero ($SPEC | update timeoutS 0)]
    ]
    for c in $bad { refused $"spec ($c.name)" { spec-validate $c.spec $LIMITS } }
    assert equal ($KIND_TIMEOUT_S | select static-site oci-image arch-base) {static-site: 7200, oci-image: 3600, arch-base: 10800}
    let nix = try { toolchain-validate {nix: "/nix/store/x", drv: "/nix/store/x.drv"}; "" } catch {|e| $e.msg }
    assert ($nix | str starts-with "nix toolchains are not offered") $"nix refusal reads ($nix)"
    for p in ["." "public" "a/b/c" "a..b"] { assert (path-inside-valid $p) $"path ($p) refused" }
}

def gate-cases [] {
    assert not (power-on-battery []) "power: a desktop"
    assert not (power-on-battery [{type: Mains, online: "1"} {type: Battery, status: Discharging}]) "power: plugged"
    assert (power-on-battery [{type: Mains, online: "0"} {type: Battery, status: Discharging}]) "power: unplugged"
    assert not (power-on-battery [{type: Battery, status: Charging}]) "power: charging"
    assert equal (gate-reasons [] false) [] "gate: idle without logins"
    assert equal (gate-reasons [{gamemode: false, obs: false}] false) [] "gate: idle"
    assert equal (gate-reasons [{gamemode: true, obs: false}] false) ["a game runs in gamemode"]
    assert equal (gate-reasons [{gamemode: false, obs: false} {gamemode: false, obs: true}] true) [
        "obs is streaming or recording" "the desktop is on battery"
    ]
    assert equal (gate-reasons [null] false) ["a login's gate state is unreadable"] "gate: a broken file is busy"
    assert equal (gate-reasons [{gamemode: "no", obs: false}] false) ["a login's gate state is unreadable"]
}

def consent-cases [] {
    let now = date now
    let once = {nonce: n1, answer: once, time: $now}
    assert equal (consent-decide true null null $now) allow "consent: trusted"
    assert equal (consent-decide false null null $now) ask "consent: unknown"
    assert equal (consent-decide false $once null $now) allow "consent: fresh once"
    assert equal (consent-decide false $once n1 $now) allow "consent: this request's once"
    assert equal (consent-decide false $once n2 $now) ask "consent: another request's answer"
    assert equal (consent-decide false ($once | update answer deny) null $now) deny "consent: deny"
    assert equal (consent-decide false ($once | update answer always) null $now) ask "consent: an unknown answer"
    let stale = $now - $CONSENT_WINDOW - 1sec
    assert equal (consent-decide false ($once | update time $stale) null $now) ask "consent: stale once"
    assert equal (consent-decide false ($once | update time ($now + 1hr)) null $now) ask "consent: a future answer"

    let request = {device: lab-builder, verb: submit, user: labworker, nonce: n1, time: $now}
    assert (request-pending $request null $now) "pending: a new request"
    assert not (request-pending $request $once $now) "pending: answered"
    assert (request-pending $request ($once | update nonce n0) $now) "pending: an older answer"
    assert not (request-pending ($request | update time ($now - 2min)) null $now) "pending: expired"
    assert not (request-pending ($request | update device "../x") null $now) "pending: a bad device"
    assert equal (action-answer once) {answer: once, trust: false}
    assert equal (action-answer always) {answer: once, trust: true}
    assert equal (action-answer deny) {answer: deny, trust: false}
    assert equal (action-answer "") {answer: deny, trust: false} "action: no answer is a deny"
}

def record-cases [] {
    let offer = offer-build [] 0 30000 $LIMITS
    assert ($offer.accepts and $offer.reason == null) "offer: idle"
    assert equal $offer.cap {
        memoryMiB: 16384, cpus: 8, kinds: [static-site oci-image arch-base], toolchains: [oci]
        timeoutS: {static-site: 7200, oci-image: 3600, arch-base: 10800}
    }
    assert equal (offer-build ["a game runs in gamemode"] 0 1 $LIMITS).reason "a game runs in gamemode"
    assert equal (offer-build [] 1 1 $LIMITS) ((offer-build [] 1 1 $LIMITS) | update accepts false | update reason "a job is running")

    let job = {job: j1, kind: static-site, commit: $COMMIT, command: $SPEC.command, spec: $SPEC}
    let run = {started: (date now), ended: (date now), exit: 0, peakMiB: 300, sha256: "ab"}
    let manifest = manifest-build $job $run {host: h, version: v}
    assert equal ($manifest | columns) [id kind commit toolchain command started ended exit peakMemoryMiB sha256 worker]
    assert equal $manifest.toolchain {oci: $IMAGE}

    let first = metrics-state null 1 null
    assert equal $first {running: 1, last: {}}
    let done = {kind: static-site, exit: 0, seconds: 12, peakMiB: 300, ended: 1}
    let second = metrics-state $first 0 $done
    assert equal $second {running: 0, last: {static-site: {exit: 0, seconds: 12, peakMiB: 300, ended: 1}}}
    let third = metrics-state $second 0 ($done | update kind arch-base | update exit 2)
    assert equal ($third.last | columns | sort) [arch-base static-site] "metrics: kinds kept apart"
    assert equal (metrics-state "garbage" 0 null) {running: 0, last: {}}

    let dir = mktemp --directory --tmpdir worker-test-XXXXXX
    let jobs = [[name files]; [running {}] [done {exit: "0", "manifest.json": "{}"}] [failed {exit: "3"}]
        [cancelled {cancelled: "busy"}] [lost {}]]
    for j in $jobs {
        mkdir ($dir | path join $j.name)
        $j.files | items {|f, text| $text | save ($dir | path join $j.name $f) } | ignore
    }
    let states = $jobs | each {|j| job-state ($dir | path join $j.name) [running] | get state }
    assert equal $states [running done failed cancelled lost]
    rm --recursive --force $dir
}

# admit and serve against a scratch root: trust, answers and the gate are files there.
def root-cases [] {
    let root = mktemp --directory --tmpdir worker-root-XXXXXX
    for d in [run/offload/gate run/offload/answers run/offload/consent var/lib/offload/trust etc/offload] {
        mkdir ($root | path join $d)
    }
    with-env {OFFLOAD_ROOT: $root} {
        assert equal (admit here offer true) null "admit: this desktop, idle"
        {device: lab-builder, since: (date now)} | to nuon | save ($root | path join var/lib/offload/trust/lab-builder.nuon)
        assert equal (admit lab-builder offer false) null "admit: trusted"
        {nonce: x, answer: deny, time: (date now)} | to nuon | save ($root | path join run/offload/answers/phone.nuon)
        assert equal (admit phone offer false) "phone was denied on this desktop"
        {gamemode: true, obs: false} | to json | save ($root | path join run/offload/gate/1000.json)
        assert equal (admit lab-builder submit false) "a game runs in gamemode" "admit: busy before trust"
    }
    # serve drops OFFLOAD_ROOT: the scratch limits never reach it
    {memoryMiB: 1024, cpus: 1} | to nuon | save ($root | path join etc/offload/limits.nuon)
    for original in ["sh -c id" "offer; id" "status ../../etc/passwd"] {
        let got = with-env {OFFLOAD_ROOT: $root, SSH_ORIGINAL_COMMAND: $original} {
            ^$nu.current-exe --no-config-file $SCRIPT serve lab-builder | complete
        }
        assert equal $got.exit_code 1 $"serve ($original): exit ($got.exit_code)"
        assert (($got.stdout | from json | get error) != "") $"serve ($original): ($got.stdout)"
    }
    let bad_device = with-env {SSH_ORIGINAL_COMMAND: offer} { ^$nu.current-exe --no-config-file $SCRIPT serve "../x" | complete }
    assert equal ($bad_device.stdout | from json) {error: "no device name"}
    rm --recursive --force $root
}

const STUB_PODMAN = '#!/bin/sh
case "$1" in
  image|pull) exit 0 ;;
  unshare) shift; exec "$@" ;;
  --cgroup-manager=cgroupfs) shift ;;
esac
[ "$1" = run ] || exit 9
for a; do case $a in --mount=*) src=${a#*src=}; src=${src%%,*} ;; esac; done
printf "%s\n" "$@" > "$STUB_LOG.podman"
mkdir -p "$src/public" && echo built > "$src/public/index.html"'
const STUB_SYSTEMD_RUN = '#!/bin/sh
printf "%s\n" "$@" > "$STUB_LOG.systemd-run"'
const STUB_SYSTEMCTL = "#!/bin/sh\nexit 0"

# submit, the unit's run and get as this desktop's own client, podman and systemd stubbed: the unit's caps, the
# container's flags, the result tar's manifest and artifact, status, and a bundle without the commit failing.
def flow-cases [] {
    let scratch = mktemp --directory --tmpdir worker-flow-XXXXXX
    let bin = $scratch | path join bin
    mkdir $bin ($scratch | path join root etc offload) ($scratch | path join root run offload metrics)
    {podman: $STUB_PODMAN, systemd-run: $STUB_SYSTEMD_RUN, systemctl: $STUB_SYSTEMCTL} | items {|name, text|
        $text | save ($bin | path join $name)
        ^chmod 755 ($bin | path join $name)
    } | ignore
    {memoryMiB: 8192, cpus: 4} | to nuon | save ($scratch | path join root etc offload limits.nuon)
    let repo = $scratch | path join repo
    ^git init --quiet $repo
    "x\n" | save ($repo | path join a.txt)
    ^git -C $repo add a.txt
    ^git -C $repo -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit --quiet -m one
    let commit = ^git -C $repo rev-parse HEAD | str trim
    let bundle = $scratch | path join repo.bundle
    ^git -C $repo bundle create --quiet $bundle HEAD
    let host = sys host | get hostname
    let env_flow = {
        OFFLOAD_ROOT: ($scratch | path join root), XDG_STATE_HOME: ($scratch | path join state)
        XDG_RUNTIME_DIR: $scratch, STUB_LOG: ($scratch | path join log), PATH: ([$bin] ++ $env.PATH)
    }
    let worker = {|command: string, input: any|
        with-env $env_flow {
            hide-env --ignore-errors SSH_CONNECTION
            if $input == null {
                ^$nu.current-exe --no-config-file $SCRIPT local $host $command | complete
            } else {
                open --raw $input | ^$nu.current-exe --no-config-file $SCRIPT local $host $command | complete
            }
        }
    }
    let spec = $SPEC | update commit $commit
    let submitted = do $worker $"submit ($spec | to json --raw)" $bundle
    assert equal $submitted.exit_code 0 $"submit: ($submitted.stdout)"
    let id = $submitted.stdout | from json | get id
    let unit = open --raw ($scratch | path join log.systemd-run) | lines
    for want in ["--slice=offload.slice" "--property=MemoryMax=4096M" "--property=CPUQuota=400%" "--property=MemorySwapMax=0" run $id] {
        assert ($want in $unit) $"systemd-run lacks ($want): ($unit)"
    }
    let ran = with-env $env_flow { ^$nu.current-exe --no-config-file $SCRIPT run $id | complete }
    assert equal $ran.exit_code 0 $"run: ($ran.stderr)"
    let container = open --raw ($scratch | path join log.podman) | lines
    for want in [--network=none --read-only --security-opt=no-new-privileges --cgroups=disabled --pull=never $IMAGE zola] {
        assert ($want in $container) $"podman lacks ($want): ($container)"
    }
    let status = do $worker $"status ($id)" null | get stdout | from json
    assert equal $status.state done $"status: ($status)"
    let out = $scratch | path join out
    mkdir $out
    with-env $env_flow { ^$nu.current-exe --no-config-file $SCRIPT local $host $"get ($id)" | ^tar --extract --directory $out }
    let manifest = open ($out | path join manifest.json)
    assert equal [$manifest.id $manifest.exit $manifest.commit] [$id 0 $commit]
    let sha = ^sha256sum ($out | path join artifact.tar.zst) | split row " " | first
    assert equal $manifest.sha256 $sha "manifest: the artifact's sha256"
    assert equal (^tar --extract --zstd --to-stdout --file ($out | path join artifact.tar.zst) public/index.html | str trim) built
    let metrics = open ($scratch | path join root run offload metrics $"(^id -u | str trim).json")
    assert equal $metrics.last.static-site.exit 0 "metrics: the finished job"

    let other = do $worker $"submit ($spec | update commit ('f' | fill --width 40 --character f) | to json --raw)" $bundle
    let failed_id = $other.stdout | from json | get id
    let failed = with-env $env_flow { ^$nu.current-exe --no-config-file $SCRIPT run $failed_id | complete }
    assert ($failed.exit_code != 0 and ($failed.stderr =~ "lacks")) $"a missing commit ran: ($failed.stderr)"
    let refused = do $worker $"submit ($spec | update output '../x' | to json --raw)" $bundle
    assert equal $refused.exit_code 1 "an escaping output was submitted"
    rm --recursive --force $scratch
}

def main [] {
    parse-cases
    spec-cases
    gate-cases
    consent-cases
    record-cases
    root-cases
    if (which git tar zstd sha256sum | length) < 4 { print --stderr "worker.test: skipped the flow: needs git, tar, zstd"; return }
    flow-cases
}
