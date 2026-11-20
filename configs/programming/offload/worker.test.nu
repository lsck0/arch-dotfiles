#!/usr/bin/env -S nu --no-config-file
# The worker's protocol by table: the original command's strict parse, the job spec's checks (kinds, ids, pinned
# images, nix refused, paths inside the checkout, the network, the caps, the cache), the submit header, the cache's
# key and eviction, the idle gate, the consent decision and the login's half of it, the offer, the manifest and the
# metrics state; then admission and serve against a scratch OFFLOAD_ROOT, and whole jobs with podman and systemd
# stubbed: a streamed image checked by its id, complete and thin packs, the cache restored, saved and kept clean.

use worker.nu [
    command-parse spec-validate toolchain-validate path-inside-valid power-on-battery gate-reasons consent-decide
    manifest-build metrics-state offer-build job-state admit header-validate cache-evict cache-key target-inside image-pin
    CONSENT_WINDOW KIND_TIMEOUT_S
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
    let id = "sha256:" + (1..64 | each { "b" } | str join)
    assert equal (spec-validate ($SPEC | update toolchain {oci: $id}) $LIMITS).toolchain.oci $id "spec: an image id"
    let cached = $SPEC | insert cache {paths: [node_modules .cache/zola]}
    assert equal (spec-validate $cached $LIMITS) $cached "spec: a cache"
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
        [short-id ($SPEC | update toolchain {oci: "sha256:abc"})]
        [bare-hex-id ($SPEC | update toolchain {oci: (1..64 | each { "b" } | str join)})]
        [cache-key-named ($SPEC | insert cache {paths: [x], key: other-repo})]
        [cache-empty ($SPEC | insert cache {paths: []})]
        [cache-dots ($SPEC | insert cache {paths: ["a/../../x"]})]
        [cache-absolute ($SPEC | insert cache {paths: [/tmp]})]
        [cache-checkout ($SPEC | insert cache {paths: ["."]})]
        [cache-git ($SPEC | insert cache {paths: [.git/hooks]})]
        [cache-repeat ($SPEC | insert cache {paths: [a a]})]
        [cache-type ($SPEC | insert cache {paths: [1]})]
    ]
    for c in $bad { refused $"spec ($c.name)" { spec-validate $c.spec $LIMITS } }
    assert equal ($KIND_TIMEOUT_S | select static-site oci-image arch-base) {static-site: 7200, oci-image: 3600, arch-base: 10800}
    let nix = try { toolchain-validate {nix: "/nix/store/x", drv: "/nix/store/x.drv"}; "" } catch {|e| $e.msg }
    assert ($nix | str starts-with "nix toolchains are not offered") $"nix refusal reads ($nix)"
    for p in ["." "public" "a/b/c" "a..b"] { assert (path-inside-valid $p) $"path ($p) refused" }
}

def header-cases [] {
    let id = $SPEC | update toolchain {oci: ("sha256:" + (1..64 | each { "b" } | str join))}
    let parent = "f" | fill --width 40 --character f
    assert equal (header-validate {pack: 10} $SPEC) {image: 0, pack: 10, shallow: []}
    assert equal (header-validate {image: 5, pack: 10, shallow: [$parent]} $id) {image: 5, pack: 10, shallow: [$parent]}
    let local = $SPEC | update toolchain {oci: ("localhost/static-site-toolchain-site@" + $id.toolchain.oci)}
    assert equal (header-validate {image: 5, pack: 10} $local).image 5 "header: a localhost pin streams"
    let bad = [
        [name header spec];
        [not-a-record [1] $SPEC]
        [no-pack {image: 5} $id]
        [zero-pack {pack: 0} $SPEC]
        [pack-over {pack: 2147483649} $SPEC]
        [image-over {image: 8589934593, pack: 1} $id]
        [negative-image {image: -1, pack: 1} $id]
        [string-pack {pack: "10"} $SPEC]
        [bundle {bundle: 10} $SPEC]
        [shallow-short {pack: 10, shallow: [abc]} $SPEC]
        [shallow-repeat {pack: 10, shallow: [$parent $parent]} $SPEC]
        [shallow-string {pack: 10, shallow: $parent} $SPEC]
        [shallow-many {pack: 10, shallow: (0..64 | each {|i| $i | fill --width 40 --character 0 --alignment right })} $SPEC]
        [streamed-by-digest {image: 5, pack: 10} $SPEC]
    ]
    for c in $bad { refused $"header ($c.name)" { header-validate $c.header $c.spec } }
}

def pin-cases [] {
    let id = "sha256:" + (1..64 | each { "c" } | str join)
    assert equal (image-pin $id) $id "pin: a bare id"
    assert equal (image-pin $"localhost/static-site-toolchain-site@($id)") $id "pin: a localhost name's digest"
    assert equal (image-pin $IMAGE) null "pin: a registry digest is no id"
    assert equal (image-pin $"localhost/x@sha256:abc") null "pin: a short digest"
    let local = $SPEC | update toolchain {oci: $"localhost/static-site-toolchain-site@($id)"}
    assert equal (spec-validate $local $LIMITS) $local "spec: the lab's localhost pin"
}

def cache-cases [] {
    let now = date now
    let entries = [[key bytes used]; [a 30 ($now - 3day)] [b 30 ($now - 1day)] [c 30 ($now - 2day)]]
    assert equal (cache-evict $entries 100 0 null) [] "evict: fits"
    assert equal (cache-evict $entries 100 20 null) [a] "evict: the oldest first"
    assert equal (cache-evict $entries 100 50 null) [a c] "evict: in order of last use"
    assert equal (cache-evict $entries 100 50 b) [a] "evict: the replaced entry is not counted"
    assert equal (cache-evict $entries 10 50 null) [a c b] "evict: everything for a big one"
    let key = cache-key lab-builder lsck0/site "sha256:01"
    assert ($key =~ '^[0-9a-f]{64}$') "key: a sha256"
    assert ($key != (cache-key lab-builder lsck0/other "sha256:01")) "key: repos share a key"
    assert ($key != (cache-key lab-builder lsck0/site "sha256:02")) "key: images share a key"
    assert ($key != (cache-key phone lsck0/site "sha256:01")) "key: devices share a key"
    assert (target-inside /w/src /w/src/a) "inside: below"
    assert (target-inside /w/src /w/src) "inside: the root"
    assert not (target-inside /w/src /w/src2/a) "inside: a sibling with the root's prefix"
    assert not (target-inside /w/src /etc) "inside: outside"
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
    assert equal (gate-reasons [] false 1) ["a login's idle gate is not running"] "gate: a missing gate is busy"
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
    let offer = offer-build [] 0 30000 $LIMITS ["sha256:01"]
    assert ($offer.accepts and $offer.reason == null) "offer: idle"
    assert equal $offer.images ["sha256:01"]
    assert equal $offer.cap {
        memoryMiB: 16384, cpus: 8, kinds: [static-site oci-image arch-base], toolchains: [oci]
        timeoutS: {static-site: 7200, oci-image: 3600, arch-base: 10800}, imageBytes: 8589934592
        packBytes: 2147483648, cacheBytes: 21474836480
    }
    assert equal (offer-build ["a game runs in gamemode"] 0 1 $LIMITS []).reason "a game runs in gamemode"
    let busy = offer-build [] 1 1 $LIMITS []
    assert equal [$busy.accepts $busy.reason] [false "a job is running"]

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
log="$STUB_LOG"
case "$1" in
  images) [ -f "$log.images" ] && sed "s/^/sha256:/; s/$/|<none>|/" "$log.images"; exit 0 ;;
  image)
    [ "$2" = exists ] && { grep -qx "${3#sha256:}" "$log.images" 2>/dev/null; exit $?; }
    exit 9 ;;
  load) echo "$STUB_LOAD_ID" >> "$log.images"; echo "Loaded image: sha256:$STUB_LOAD_ID"; exit 0 ;;
  untag) echo "$*" >> "$log.untag"; exit 0 ;;
  unshare) shift; exec "$@" ;;
  --cgroup-manager=cgroupfs) shift ;;
esac
[ "$1" = run ] || exit 9
for a; do case $a in --mount=*) src=${a#*src=}; src=${src%%,*} ;; esac; done
printf "%s\n" "$@" > "$log.podman"
if [ -e "$src/.cache/build/x" ]; then cat "$src/.cache/build/x"; else echo none; fi > "$log.restored"
mkdir -p "$src/public" "$src/.cache/build" && echo built > "$src/public/index.html"
for last; do :; done
echo "$last" > "$src/.cache/build/x"
case "$last" in
  fail) exit 3 ;;
  evil) ln -s /etc "$src/.cache/build/evil" ;;
esac
exit 0'
const STUB_SYSTEMD_RUN = '#!/bin/sh
printf "%s\n" "$@" > "$STUB_LOG.systemd-run"'
const STUB_SYSTEMCTL = "#!/bin/sh\nexit 0"

def git-commit [repo: path, file: string, text: string]: nothing -> string {
    $text | save --force ($repo | path join $file)
    ^git -C $repo add $file
    ^git -C $repo -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit --quiet -m $file
    ^git -C $repo rev-parse HEAD | str trim
}

# The commit's pack as the lab makes it (pack-objects fed the commit alone in a checkout one commit deep), its thin
# pack against its parent, or the commit and its trees without their blobs.
def pack-write [repo: path, commit: string, file: path, --thin, --treeless]: nothing -> nothing {
    let script = if $thin {
        'printf "%s\n--not\n%s^\n" "$2" "$2" | git -C "$1" pack-objects --stdout --revs --thin --quiet > "$3"'
    } else if $treeless {
        '{ echo "$2"; git -C "$1" rev-parse "$2^{tree}"; git -C "$1" ls-tree -r -d --format="%(objectname)" "$2"; } | git -C "$1" pack-objects --stdout --quiet > "$3"'
    } else {
        'd=$(mktemp -d) && git clone --quiet --depth 1 "file://$1" "$d/c" && echo "$2" | git -C "$d/c" pack-objects --stdout --revs --quiet > "$3"; rm -rf "$d"'
    }
    ^sh -c $script sh $repo $commit $file
}

# A docker-archive of one image whose config holds text: its id is the config's sha256.
def archive-write [dir: path, text: string]: nothing -> record<file: path, id: string> {
    let tree = $dir | path join $"archive-($text)"
    mkdir $tree
    let config = $"{\"config\": \"($text)\"}"
    let hex = $config | hash sha256
    $config | save ($tree | path join $"($hex).json")
    [{Config: $"($hex).json", RepoTags: ["ghcr.io/evil/redirect:latest"], Layers: []}] | to json | save ($tree | path join manifest.json)
    let file = $dir | path join $"archive-($text).tar"
    ^tar --create --file $file --directory $tree -- manifest.json $"($hex).json"
    {file: $file, id: $"sha256:($hex)"}
}

# submit, the unit's run and get as this desktop's own client with podman and systemd stubbed.
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
    mkdir ($repo | path join keep)
    git-commit $repo keep/h "unchanged\n" | ignore
    let parent = git-commit $repo a.txt "one\n"
    let commit = git-commit $repo a.txt "two\n"
    let pack = $scratch | path join closure.pack
    pack-write $repo $commit $pack
    let thin = $scratch | path join thin.pack
    pack-write $repo $commit $thin --thin
    let treeless = $scratch | path join treeless.pack
    pack-write $repo $commit $treeless --treeless
    let image = archive-write $scratch good
    let forged = archive-write $scratch forged
    let host = sys host | get hostname
    let log = $scratch | path join log
    let env_flow = {
        OFFLOAD_ROOT: ($scratch | path join root), XDG_STATE_HOME: ($scratch | path join state)
        XDG_CACHE_HOME: ($scratch | path join cache), XDG_RUNTIME_DIR: $scratch, STUB_LOG: $log
        STUB_LOAD_ID: ($image.id | str replace "sha256:" ""), PATH: ([$bin] ++ $env.PATH)
    }
    # header line, image archive, pack: the submit's stdin
    let submit = {|spec: record, pack: path, archive: any|
        let input = $scratch | path join input
        let sizes = {pack: (ls $pack | get 0.size | into int), shallow: [$parent]}
        let header = if $archive == null { $sizes } else { $sizes | insert image (ls $archive | get 0.size | into int) }
        $"($header | to json --raw)\n" | save --force $input
        ^sh -c 'cat "$@"' sh ...([$archive $pack] | compact) | save --append --raw $input
        with-env $env_flow {
            hide-env --ignore-errors SSH_CONNECTION
            open --raw $input | ^$nu.current-exe --no-config-file $SCRIPT local $host $"submit ($spec | to json --raw)" | complete
        }
    }
    let run = {|id: string| with-env $env_flow { ^$nu.current-exe --no-config-file $SCRIPT run $id | complete } }
    let status = {|id: string|
        with-env $env_flow { ^$nu.current-exe --no-config-file $SCRIPT local $host $"status ($id)" | complete } | get stdout | from json
    }
    let toolchain = $"localhost/static-site-toolchain-site@($image.id)"
    let spec = $SPEC | update commit $commit | update toolchain {oci: $toolchain} | insert cache {paths: [.cache/build]}
    | update command [build v1]

    let refused = do $submit $spec $pack null
    assert ($refused.exit_code == 1 and ($refused.stdout =~ "not on this worker")) $"an absent image was not refused: ($refused.stdout)"
    let by_digest = do $submit ($spec | update toolchain {oci: $IMAGE}) $pack $image.file
    assert ($by_digest.stdout =~ "pinned by its image id") $"an image streamed under a registry digest: ($by_digest.stdout)"

    let first = do $submit $spec $pack $image.file
    assert equal $first.exit_code 0 $"submit: ($first.stdout)"
    let id = $first.stdout | from json | get id
    let unit = open --raw $"($log).systemd-run" | lines
    for want in ["--slice=offload.slice" "--property=MemoryMax=4096M" "--property=CPUQuota=400%" "--property=MemorySwapMax=0" run $id] {
        assert ($want in $unit) $"systemd-run lacks ($want): ($unit)"
    }
    let ran = do $run $id
    assert equal $ran.exit_code 0 $"run: ($ran.stderr)"
    let container = open --raw $"($log).podman" | lines
    let hex = $image.id | str replace "sha256:" ""
    for want in [--network=none --read-only --security-opt=no-new-privileges --cgroups=disabled --pull=never $hex build] {
        assert ($want in $container) $"podman lacks ($want): ($container)"
    }
    assert not ($container | any { $in =~ "ghcr.io|localhost/" }) "the container ran by a name"
    assert (open --raw $"($log).untag" | str contains $hex) "the loaded image kept its names"
    assert equal (open --raw $"($log).restored" | str trim) none "a first job found a cache"
    assert equal (do $status $id).state done
    let out = $scratch | path join out
    mkdir $out
    with-env $env_flow { ^$nu.current-exe --no-config-file $SCRIPT local $host $"get ($id)" | ^tar --extract --directory $out }
    let manifest = open ($out | path join manifest.json)
    assert equal [$manifest.id $manifest.exit $manifest.commit $manifest.toolchain.oci] [$id 0 $commit $toolchain]
    let sha = ^sha256sum ($out | path join artifact.tar.zst) | split row " " | first
    assert equal $manifest.sha256 $sha "manifest: the artifact's sha256"
    assert equal (^tar --extract --zstd --to-stdout --file ($out | path join artifact.tar.zst) public/index.html | str trim) built
    let metrics = open ($scratch | path join root run offload metrics $"(^id -u | str trim).json")
    assert equal $metrics.last.static-site.exit 0 "metrics: the finished job"
    let offer = with-env $env_flow { ^$nu.current-exe --no-config-file $SCRIPT local $host offer | complete } | get stdout | from json
    assert ($image.id in $offer.images) $"offer: the loaded image is not listed: ($offer.images)"

    # the image is held now: no stream; the cache from the first job is restored, a failed job writes none
    let key = cache-key $host $spec.repo $image.id
    let cached = $scratch | path join cache offload $key tree .cache build x
    assert equal (open --raw $cached | str trim) v1 "cache: the first job's path"
    let jobs = [[last restored kept]; [fail v1 v1] [v2 v1 v2] [evil v2 v2]]
    for j in $jobs {
        let next = do $submit ($spec | update command [build $j.last]) $pack null
        let next_id = $next.stdout | from json | get id
        do $run $next_id | ignore
        assert equal (open --raw $"($log).restored" | str trim) $j.restored $"cache: ($j.last) found ($j.restored)"
        assert equal (open --raw $cached | str trim) $j.kept $"cache: after ($j.last) it holds the wrong job's"
    }
    assert not ($scratch | path join cache offload $key tree .cache build evil | path exists --no-symlink) "cache: saved a link out"

    # a cached link out of the checkout planted in the store is dropped on restore
    ^ln -s /etc ($scratch | path join cache offload $key tree .cache build evil)
    let planted = do $submit ($spec | update command [build v3]) $pack null
    let planted_id = $planted.stdout | from json | get id
    let planted_run = do $run $planted_id
    assert ($planted_run.stderr =~ "link out of the checkout") $"cache: a planted link was restored: ($planted_run.stderr)"
    assert equal (open --raw $"($log).restored" | str trim) none "cache: the tree with a link out was restored"

    let lines_before = open --raw $"($log).images" | lines | length
    let mismatch = do $submit $spec $pack $forged.file
    let mismatch_id = $mismatch.stdout | from json | get id
    let mismatch_run = do $run $mismatch_id
    assert ($mismatch_run.exit_code != 0 and ($mismatch_run.stderr =~ "not the pinned")) $"a forged image ran: ($mismatch_run.stderr)"
    assert equal (open --raw $"($log).images" | lines | length) $lines_before "a forged image was loaded"
    assert equal (do $status $mismatch_id).state failed

    let thin_job = do $submit ($spec | update command [build v4]) $thin null
    let thin_run = do $run ($thin_job.stdout | from json | get id)
    assert ($thin_run.exit_code != 0 and ($thin_run.stderr =~ "complete closure")) $"a thin pack checked out: ($thin_run.stderr)"
    let treeless_job = do $submit ($spec | update command [build v5]) $treeless null
    let treeless_run = do $run ($treeless_job.stdout | from json | get id)
    assert ($treeless_run.exit_code != 0 and ($treeless_run.stderr =~ "missing")) $"a pack without blobs checked out: ($treeless_run.stderr)"
    let other = do $submit ($spec | update commit $parent) $pack null
    let other_run = do $run ($other.stdout | from json | get id)
    assert ($other_run.exit_code != 0) "a pack of another commit checked out"
    let escaping = do $submit ($spec | update output '../x') $pack null
    assert equal $escaping.exit_code 1 "an escaping output was submitted"
    rm --recursive --force $scratch
}

def main [] {
    parse-cases
    spec-cases
    header-cases
    pin-cases
    cache-cases
    gate-cases
    consent-cases
    record-cases
    root-cases
    if (which git tar zstd sha256sum | length) < 4 { print --stderr "worker.test: skipped the flow: needs git, tar, zstd"; return }
    flow-cases
}
