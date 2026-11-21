#!/usr/bin/env -S nu --no-config-file
# offload's worker on the target: one protocol for every client. The lab's builder reaches it as labworker through its
# forced ssh command (`serve <device>`), the notebook and this desktop through `offload worker` (`local <device>`).
# Verbs: offer, submit <json> with its sources on stdin (a header line, then the image archive if streamed, then a
# complete pack of the commit), status <id>, get <id> (the result tar on stdout), cancel <id>, gc. A job is admitted only while the desktop is idle (no game in gamemode, no obs output, on mains) and its device
# consents; it runs in a transient unit of the caller's own user manager inside offload.slice, its oci toolchain in
# rootless podman with only its checkout mounted. Self-contained: labworker runs the root-owned copy in
# /usr/local/lib/offload and reads nothing of the repo.

export const VERBS = [offer submit status get cancel gc]
export const OCI_KINDS = [static-site oci-image arch-base]
export const KIND_RUN = "run"
export const KIND_AGENT = "agent"
export const KIND_TIMEOUT_S = {static-site: 7200, oci-image: 3600, arch-base: 10800, run: 86400}
const NETWORK_KINDS = [arch-base]
const SPEC_KEYS = [kind repo commit toolchain command workdir output network memoryMiB cpus timeoutS]
const SPEC_OPTIONAL = [cache]
const HEADER_KEYS = [image pack shallow]
const SHALLOW_MAX = 64
export const JOB_ID = '^[a-z0-9][a-z0-9._-]{0,63}$'
export const DEVICE = '^[a-z0-9][a-z0-9-]{0,39}$'
const COMMIT = '^[0-9a-f]{40}$'
const REPO_NAME = '^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$'
# registry host (dotted, with a port, or localhost), path, optional tag, then the digest: never a tag alone
const OCI_IMAGE = '^(?:[a-z0-9-]+(?:\.[a-z0-9-]+)+(?::\d+)?|localhost(?::\d+)?)/[a-z0-9]+(?:(?:[._]|__|-+|/)[a-z0-9]+)*(?::[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?@sha256:[0-9a-f]{64}$'
# an image id, the digest of the image's config: what survives podman save and load, so the pin of a streamed image
const IMAGE_ID = '^sha256:[0-9a-f]{64}$'
# a local name whose digest is the image id (the lab's toolchains), the name never resolved
const LOCAL_PIN = '^localhost/[^@]+@(?<id>sha256:[0-9a-f]{64})$'
# a docker-archive's config member: <hex>.json (docker) or blobs/sha256/<hex> (podman)
const ARCHIVE_CONFIG = '^(?:blobs/sha256/)?[0-9a-f]{64}(?:\.json)?$'
const NIX_REFUSAL = "nix toolchains are not offered: nix-daemon's builders run outside the job's unit and its cap, and the derivation's closure is not on this machine"
const COMMAND_MAX = 256
const ARG_MAX = 4096
const ORIGINAL_MAX = 65536
const MEMORY_MIN_MIB = 256
const HEADER_MAX = 4096
const PACK_MAX = 2147483648
const IMAGE_MAX = 8589934592
const DISK_MIN = 21474836480
const CACHE_PATHS_MAX = 16
const CACHE_KEY_MAX = 21474836480
const CACHE_TOTAL_MAX = 64424509440
const IMAGE_UNUSED = 7day
const RUNNING_MAX = 1

const SELF = path self
const GATE_DIR = "/run/offload/gate"
const CONSENT_DIR = "/run/offload/consent"
const ANSWER_DIR = "/run/offload/answers"
const METRICS_DIR = "/run/offload/metrics"
export const TRUST_DIR = "/var/lib/offload/trust"
# {memoryMiB, cpus}: the module's caps, written by its system verb
const LIMITS = "/etc/offload/limits.nuon"
const POWER = "/sys/class/power_supply"
const SLICE = "offload.slice"
export const UNIT_PREFIX = "offload-"
const NICE = 10
const TASKS_MAX = 4096
const IO_WEIGHT = 10
# past the job's own timeout podman already killed it; this only catches a wedged runner
const RUNTIME_MARGIN_S = 600
export const CONSENT_WAIT = 60sec
export const CONSENT_WINDOW = 15min
const CONSENT_POLL = 1sec
const GC_AGE = 24hr
const STAMP_FORMAT = "%Y%m%d-%H%M%S"
const NONCE_BYTES = 2

export const JOB_FILE = "job.nuon"
export const EXIT_FILE = "exit"
export const CANCEL_FILE = "cancelled"
export const LOG_FILE = "log"
const PACK_FILE = "source.pack"
const IMAGE_FILE = "image.tar"
export const ERROR_FILE = "error"
const CACHE_TREE = "tree"
const CACHE_USED = "used"
const SOURCE_DIR = "src"
const ARTIFACT = "artifact.tar.zst"
const MANIFEST = "manifest.json"
const RESULT = "result.tar"
const SANDBOX = "/src"

def fail [msg: string] { error make {msg: $msg} }

# A shared path of the worker; OFFLOAD_ROOT prefixes them all for the tests, never for serve, which drops it.
export def state-at [path: string]: nothing -> string { ($env.OFFLOAD_ROOT? | default "") + $path }

def is-string [value: any]: nothing -> bool { ($value | describe) == "string" }

def is-int [value: any]: nothing -> bool { ($value | describe) == "int" }

# The verb and its argument of an ssh original command, refused unless it is exactly one of VERBS with the argument
# that verb takes: nothing, a job id, or (submit) the job's JSON.
export def command-parse [original: string]: nothing -> record<verb: string, arg: string> {
    if ($original | str length --utf-8-bytes) > $ORIGINAL_MAX { fail "the command is too long" }
    let parsed = $original | parse --regex '(?s)^(?<verb>[a-z]+)(?: (?<arg>.*))?$' | get --optional 0
    if $parsed == null or $parsed.verb not-in $VERBS {
        fail $"not a worker command; one of ($VERBS | str join ', ')"
    }
    let arg = $parsed.arg? | default ""
    match $parsed.verb {
        "offer" | "gc" => { if $arg != "" { fail $"($parsed.verb) takes no argument" } }
        "submit" => { if $arg == "" { fail "submit takes the job as JSON" } }
        _ => { if not ($arg =~ $JOB_ID) { fail $"($parsed.verb) takes a job id" } }
    }
    {verb: $parsed.verb, arg: $arg}
}

export def path-inside-valid [path: any]: nothing -> bool {
    ((is-string $path) and $path != "" and not ($path | str starts-with "/") and not ($path | str contains (char nul))
        and ($path | split row "/" | all { $in != ".." }))
}

export def toolchain-validate [toolchain: any]: nothing -> nothing {
    if ($toolchain | describe) !~ '^record' { fail "toolchain is no object" }
    let keys = $toolchain | columns
    if "nix" in $keys or "drv" in $keys { fail $NIX_REFUSAL }
    if $keys != [oci] { fail "toolchain is {oci: <sha256:<id> or registry/name@sha256:<digest>>}" }
    if not (is-string $toolchain.oci) or not ($toolchain.oci =~ $IMAGE_ID or $toolchain.oci =~ $OCI_IMAGE) {
        fail "toolchain.oci is no pinned image: sha256:<64 hex image id> or registry/name[:tag]@sha256:<64 hex>"
    }
}

# A job's cache: only paths, each relative and inside the checkout, none in .git; the key is the worker's own.
export def cache-validate [cache: any]: nothing -> nothing {
    if ($cache | describe) !~ '^record' or ($cache | columns) != [paths] { fail "cache is {paths: [...]}" }
    let paths = $cache.paths
    if ($paths | describe) !~ '^list' or ($paths | is-empty) or ($paths | length) > $CACHE_PATHS_MAX {
        fail $"cache.paths is a list of 1 to ($CACHE_PATHS_MAX) paths"
    }
    for p in $paths {
        if not (path-inside-valid $p) or $p == "." or ($p | split row "/" | first) == ".git" {
            fail "cache.paths holds a path that is not inside the checkout, the checkout itself or in .git"
        }
    }
    if ($paths | uniq | length) != ($paths | length) { fail "cache.paths repeats a path" }
}

# A submitted job, checked whole against limits {memoryMiB, cpus}; its first fault is the error.
export def spec-validate [spec: any, limits: record]: nothing -> record {
    if ($spec | describe) !~ '^record' { fail "the job is no JSON object" }
    let keys = $spec | columns
    let missing = $SPEC_KEYS | where $it not-in $keys
    if ($missing | is-not-empty) { fail $"the job lacks ($missing | str join ', ')" }
    let unknown = $keys | where $it not-in ($SPEC_KEYS ++ $SPEC_OPTIONAL)
    if ($unknown | is-not-empty) { fail $"the job has unknown keys ($unknown | str join ', ')" }
    if not (is-string $spec.kind) or $spec.kind not-in $OCI_KINDS { fail $"kind is one of ($OCI_KINDS | str join ', ')" }
    if not (is-string $spec.repo) or not ($spec.repo =~ $REPO_NAME) or ($spec.repo | str contains "..") {
        fail "repo is no repo name"
    }
    if not (is-string $spec.commit) or not ($spec.commit =~ $COMMIT) { fail "commit is no full 40-hex commit id" }
    toolchain-validate $spec.toolchain
    let command = $spec.command
    if ($command | describe) !~ '^list' or ($command | is-empty) or ($command | length) > $COMMAND_MAX {
        fail $"command is a list of 1 to ($COMMAND_MAX) arguments"
    }
    let bad = $command | where {|a|
        not (is-string $a) or ($a | str length --utf-8-bytes) > $ARG_MAX or ($a | str contains (char nul))
    }
    if ($bad | is-not-empty) { fail "command holds an argument that is no string, too long or with a NUL" }
    for field in [workdir output] {
        if not (path-inside-valid ($spec | get $field)) { fail $"($field) is no relative path inside the checkout" }
    }
    if ($spec.network | describe) != "bool" { fail "network is a bool" }
    if $spec.network and $spec.kind not-in $NETWORK_KINDS { fail $"only ($NETWORK_KINDS | str join ', ') may use the network" }
    if not (is-int $spec.memoryMiB) or $spec.memoryMiB < $MEMORY_MIN_MIB or $spec.memoryMiB > $limits.memoryMiB {
        fail $"memoryMiB is ($MEMORY_MIN_MIB) to ($limits.memoryMiB)"
    }
    if ($spec.cpus | describe) not-in [int float] or $spec.cpus <= 0 or $spec.cpus > $limits.cpus {
        fail $"cpus is above 0 and at most ($limits.cpus)"
    }
    let timeout_max = $KIND_TIMEOUT_S | get $spec.kind
    if not (is-int $spec.timeoutS) or $spec.timeoutS < 1 or $spec.timeoutS > $timeout_max {
        fail $"timeoutS is 1 to ($timeout_max) for ($spec.kind)"
    }
    if "cache" in $keys { cache-validate $spec.cache }
    $spec
}

# The image id a ref pins: a bare sha256:<id>, or localhost/<name>@sha256:<id>; null for a registry digest.
export def image-pin [ref: string]: nothing -> any {
    if $ref =~ $IMAGE_ID { return $ref }
    $ref | parse --regex $LOCAL_PIN | get --optional 0.id
}

# The submit header line {image?, pack, shallow?}: the byte counts of what follows it on stdin, the image archive
# first, and the commit's parents the pack leaves out. A streamed image must be pinned by its id, the one pin a loaded
# archive can be checked against.
export def header-validate [header: any, spec: record]: nothing -> record<image: int, pack: int, shallow: list<string>> {
    if ($header | describe) !~ '^record' { fail "the header is no JSON object" }
    let unknown = $header | columns | where $it not-in $HEADER_KEYS
    if ($unknown | is-not-empty) { fail $"the header has unknown keys ($unknown | str join ', ')" }
    let pack = $header.pack?
    if not (is-int $pack) or $pack < 1 or $pack > $PACK_MAX { fail $"header.pack is 1 to ($PACK_MAX) bytes" }
    let image = $header.image? | default 0
    if not (is-int $image) or $image < 0 or $image > $IMAGE_MAX { fail $"header.image is 0 to ($IMAGE_MAX) bytes" }
    if $image > 0 and (image-pin $spec.toolchain.oci) == null {
        fail "a streamed image is pinned by its image id: toolchain.oci is sha256:<id> or localhost/<name>@sha256:<id>"
    }
    let shallow = $header.shallow? | default []
    let ids = ($shallow | describe) =~ '^list' and ($shallow | all { (is-string $in) and ($in =~ $COMMIT) })
    if not $ids or ($shallow | length) > $SHALLOW_MAX or ($shallow | uniq | length) != ($shallow | length) {
        fail $"header.shallow is a list of at most ($SHALLOW_MAX) distinct 40-hex commit ids"
    }
    {image: $image, pack: $pack, shallow: $shallow}
}

# The cache entries to evict, least recently used first, so the rest and an incoming entry of incoming bytes fit
# max; keep (the entry being replaced) is never counted nor evicted.
export def cache-evict [entries: list<record>, max: int, incoming: int, keep: any]: nothing -> list<string> {
    let rest = $entries | where key != $keep | sort-by used
    let total = $rest | reduce --fold $incoming {|e, acc| $acc + $e.bytes }
    $rest | reduce --fold {total: $total, evict: []} {|e, acc|
        if $acc.total <= $max { $acc } else { {total: ($acc.total - $e.bytes), evict: ($acc.evict | append $e.key)} }
    } | get evict
}

# The worker's cache key: the device, the repo and the image id; the job never names it.
export def cache-key [device: string, repo: string, image: string]: nothing -> string {
    [$device $repo $image] | str join "\n" | hash sha256
}

# A link target (realpath -m) inside root.
export def target-inside [root: string, target: string]: nothing -> bool {
    $target == $root or ($target | str starts-with $"($root)/")
}

# Whether the machine runs on battery: a discharging battery and no mains or usb supply online. A desktop has neither.
export def power-on-battery [supplies: list<record>]: nothing -> bool {
    if ($supplies | any {|s| $s.type? in [Mains USB] and $s.online? == "1" }) { return false }
    $supplies | any {|s| $s.type? == "Battery" and $s.status? == "Discharging" }
}

# Why the desktop is not idle, from each login's gate state {gamemode, obs}, the logins whose gate is missing, and the
# power; empty when it is. A missing gate is busy: the worker never runs past a gate that is down.
export def gate-reasons [sessions: list<any>, on_battery: bool, missing: int = 0]: nothing -> list<string> {
    let valid = $sessions | where {|s|
        ($s | describe) =~ '^record' and ($s.gamemode? | describe) == "bool" and ($s.obs? | describe) == "bool"
    }
    [
        (if ($valid | length) != ($sessions | length) { "a login's gate state is unreadable" })
        (if $missing > 0 { "a login's idle gate is not running" })
        (if ($valid | any { $in.gamemode }) { "a game runs in gamemode" })
        (if ($valid | any { $in.obs }) { "obs is streaming or recording" })
        (if $on_battery { "the desktop is on battery" })
    ] | compact
}

# allow, deny or ask for a device: a trusted one is allowed; else the answer the desktop gave, while it is fresh and,
# with a nonce, the answer to that very request.
export def consent-decide [trusted: bool, answer: any, nonce: any, now: datetime]: nothing -> string {
    if $trusted { return "allow" }
    if ($answer | describe) !~ '^record' { return "ask" }
    let time = try { $answer.time | into datetime } catch { return "ask" }
    if $now - $time > $CONSENT_WINDOW or $time > $now { return "ask" }
    if $nonce != null and $answer.nonce? != $nonce { return "ask" }
    match $answer.answer? { "once" => "allow", "deny" => "deny", _ => "ask" }
}

export def manifest-build [job: record, run: record, worker: record]: nothing -> record {
    {
        id: $job.job, kind: $job.kind, commit: $job.commit, toolchain: $job.spec.toolchain, command: $job.command
        started: ($run.started | format date "%+"), ended: ($run.ended | format date "%+"), exit: $run.exit
        peakMemoryMiB: $run.peakMiB, sha256: $run.sha256, worker: $worker
    }
}

# The worker's metrics state: its running jobs and each kind's last finished job, finished one replacing its kind's.
export def metrics-state [previous: any, running: int, finished: any]: nothing -> record {
    let last = if ($previous | describe) =~ '^record' and ($previous.last? | describe) =~ '^record' { $previous.last } else { {} }
    let last = if $finished == null { $last } else {
        $last | upsert $finished.kind ($finished | reject kind)
    }
    {running: $running, last: $last}
}

export def offer-build [reasons: list<string>, running: int, free_mib: int, limits: record, images: list<string>]: nothing -> record {
    let reason = if ($reasons | is-not-empty) { $reasons | str join "; " } else if $running >= $RUNNING_MAX {
        "a job is running"
    }
    {
        accepts: ($reason == null), reason: $reason, freeMemoryMiB: $free_mib, images: $images
        cap: {
            memoryMiB: $limits.memoryMiB, cpus: $limits.cpus, kinds: $OCI_KINDS, toolchains: [oci]
            timeoutS: ($KIND_TIMEOUT_S | select ...$OCI_KINDS), imageBytes: $IMAGE_MAX, packBytes: $PACK_MAX
            cacheBytes: $CACHE_KEY_MAX
        }
    }
}

export def job-id [device: string, time: datetime, nonce: string]: nothing -> string {
    $"($device)-($time | format date $STAMP_FORMAT)-($nonce)"
}

def save-atomic [path: path]: string -> nothing {
    let text = $in
    let tmp = ^mktemp --tmpdir=($path | path dirname) $".($path | path basename).XXXXXX" | str trim
    try {
        $text | save --force $tmp
        ^chmod 644 $tmp
        ^mv --force $tmp $path
    } catch {|e|
        rm --force $tmp
        fail $e.msg
    }
}

def uid []: nothing -> string { ^id -u | str trim }

# The caller's user manager, also from an ssh session without pam (sshd's UsePAM is off): labworker lingers.
def manager-env []: nothing -> record {
    let runtime = $env.XDG_RUNTIME_DIR? | default $"/run/user/(uid)"
    {XDG_RUNTIME_DIR: $runtime, DBUS_SESSION_BUS_ADDRESS: $"unix:path=($runtime)/bus"}
}

def jobs-dir []: nothing -> path {
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)
    $state | path join offload jobs
}

export def unit-name [id: string]: nothing -> string { $"($UNIT_PREFIX)($id).service" }

export def units-active []: nothing -> list<string> {
    with-env (manager-env) {
        ^systemctl --user list-units $"($UNIT_PREFIX)*" --type=service --state=active,activating --plain --no-legend
    } | lines | each { split row " " | first | str replace --regex $'^($UNIT_PREFIX)' '' | str replace --regex '\.service$' '' }
    | where $it =~ '-\d{8}-\d{6}-[0-9a-f]+$'
}

def limits-load []: nothing -> record {
    let limits = try { open (state-at $LIMITS) } catch { fail "the worker is not set up here (no /etc/offload/limits.nuon)" }
    if not (is-int $limits.memoryMiB?) or ($limits.cpus? | describe) not-in [int float] { fail $"($LIMITS) is malformed" }
    $limits
}

def gate-sessions []: nothing -> list<any> {
    let dir = state-at $GATE_DIR
    if not ($dir | path exists) { return [] }
    glob $"($dir)/*.json" | each {|f| try { open $f } catch { null } }
}

def power-supplies []: nothing -> list<record> {
    glob $"(state-at $POWER)/*" | each {|d|
        let read = {|name| try { open --raw ($d | path join $name) | str trim } catch { null } }
        {type: (do $read type), online: (do $read online), status: (do $read status)}
    }
}

# the offload group's logins with a running manager: each one owes a gate file
def gate-missing []: nothing -> int {
    let members = try { open --raw (state-at /etc/group) } catch { "" } | lines | parse "{name}:{x}:{gid}:{users}"
    | where name == offload | get --optional 0.users | default "" | split row "," | where $it != ""
    $members | each {|user| try { ^id -u $user | str trim } catch { null } } | compact
    | where {|uid| (state-at $"/run/user/($uid)" | path exists) and not (state-at $"($GATE_DIR)/($uid).json" | path exists) }
    | length
}

export def gate-now []: nothing -> list<string> {
    gate-reasons (gate-sessions) (power-on-battery (power-supplies)) (gate-missing)
}

def free-memory-mib []: nothing -> int {
    open /proc/meminfo | lines | parse --regex '^MemAvailable:\s+(?<kb>\d+) kB' | get --optional 0.kb | default 0
    | into int | $in // 1024
}

def answer-read [device: string]: nothing -> any {
    try { open (state-at $ANSWER_DIR | path join $"($device).nuon") } catch { null }
}

export def trust-has [device: string]: nothing -> bool {
    state-at $TRUST_DIR | path join $"($device).nuon" | path exists
}

# Null when the device may go on, else why not: a trusted device, a fresh answer, or the desktop asked now (a
# notification with Allow once, Always allow this device, Deny) and its answer awaited; no answer is a deny.
def consent [device: string, verb: string, local: bool]: nothing -> any {
    if $local { return null }
    let decided = consent-decide (trust-has $device) (answer-read $device) null (date now)
    if $decided == "allow" { return null }
    if $decided == "deny" { return $"($device) was denied on this desktop" }
    let dir = state-at $CONSENT_DIR
    if not ($dir | path exists) { return "the desktop cannot ask for consent here" }
    let nonce = random binary 8 | encode hex --lower
    let request = {device: $device, verb: $verb, user: (^id -un | str trim), nonce: $nonce, time: (date now)}
    try { $request | to nuon | save-atomic ($dir | path join $"($device).nuon") } catch {
        return "another request of this device awaits its answer"
    }
    let deadline = (date now) + $CONSENT_WAIT
    while (date now) < $deadline {
        sleep $CONSENT_POLL
        match (consent-decide false (answer-read $device) $nonce (date now)) {
            "allow" => { return null }
            "deny" => { return $"($device) was denied on this desktop" }
        }
    }
    $"($device) got no answer on this desktop"
}

# Null when a job may start now, else why not: the idle gate first, so a game is never interrupted by a question.
export def admit [device: string, verb: string, local: bool]: nothing -> any {
    let reasons = gate-now
    if ($reasons | is-not-empty) { return ($reasons | str join "; ") }
    consent $device $verb $local
}

def metrics-file []: nothing -> path { state-at $METRICS_DIR | path join $"(uid).json" }

# Refreshes this user's metrics state; finished: the job that just ended, {kind, exit, seconds, peakMiB, ended}.
export def metrics-update [finished: any = null]: nothing -> nothing {
    if not (state-at $METRICS_DIR | path exists) { return }
    let file = metrics-file
    let previous = try { open $file } catch { null }
    try { metrics-state $previous (units-active | length) $finished | to json --raw | save-atomic $file } catch { }
}

def job-dir [id: string]: nothing -> path {
    if not ($id =~ $JOB_ID) { fail "no job id" }
    jobs-dir | path join $id
}

# The job's record, only for the device that submitted it (local: any of the caller's own).
def job-load [id: string, device: string, local: bool]: nothing -> record {
    let file = job-dir $id | path join $JOB_FILE
    let job = try { open $file } catch { fail $"no job ($id)" }
    if not $local and $job.client? != $device { fail $"no job ($id)" }
    $job
}

export def job-state [dir: path, active: list<string>]: nothing -> record {
    let read = {|name| try { open --raw ($dir | path join $name) | str trim } catch { null } }
    let id = $dir | path basename
    let cancelled = do $read $CANCEL_FILE
    let error = do $read $ERROR_FILE
    let exit = do $read $EXIT_FILE
    let state = if $cancelled != null { "cancelled" } else if $exit != null {
        if $exit == "0" and ($dir | path join $MANIFEST | path exists) { "done" } else { "failed" }
    } else if $id in $active { "running" } else { "lost" }
    {id: $id, state: $state, exit: (if $exit != null { $exit | into int }), reason: ($cancelled | default $error)}
}

# Marks the job cancelled with why and stops its unit; a finished job stays as it is.
export def job-cancel [dir: path, reason: string]: nothing -> nothing {
    if ($dir | path join $EXIT_FILE | path exists) { return }
    $reason | save --force ($dir | path join $CANCEL_FILE)
    with-env (manager-env) { do { ^systemctl --user stop (unit-name ($dir | path basename)) } | complete | ignore }
}

# The images this user's store holds: each id (sha256:...) and each registry/name@sha256 digest it is known by.
def images-held []: nothing -> list<string> {
    let got = do { ^podman images --no-trunc --format "{{.ID}}|{{.Repository}}|{{.Digest}}" } | complete
    if $got.exit_code != 0 { return [] }
    $got.stdout | lines | where $it != "" | each {|l|
        let f = $l | split row "|"
        [$f.0 (if ($f | length) == 3 and $f.1 != "<none>" and $f.2 =~ '^sha256:' { $"($f.1)@($f.2)" })]
    } | flatten | compact | uniq
}

def image-hex [id: string]: nothing -> string { $id | str replace --regex '^sha256:' '' }

def image-exists [ref: string]: nothing -> bool { (do { ^podman image exists $ref } | complete).exit_code == 0 }

def verb-offer [device: string, local: bool]: nothing -> record {
    let limits = limits-load
    let running = units-active | length
    let reason = admit $device offer $local
    offer-build ([$reason] | compact) $running (free-memory-mib) $limits (images-held)
}

# One line from stdin, read byte by byte so nothing past its newline is taken.
def header-read []: nothing -> any {
    let got = do { ^bash -c $"LC_ALL=C IFS= read -r -n ($HEADER_MAX + 1) line || exit 1; printf '%s' \"$line\"" } | complete
    if $got.exit_code != 0 or ($got.stdout | str length --utf-8-bytes) > $HEADER_MAX { fail "stdin starts with no header line" }
    try { $got.stdout | from json } catch { fail "the header is no JSON" }
}

# Exactly bytes of stdin into file; head reads no further than it writes.
def stdin-take [file: path, bytes: int, what: string]: nothing -> nothing {
    ^head --bytes=($bytes) o> $file
    if (ls $file | get 0.size | into int) != $bytes { fail $"stdin ended inside the ($what)" }
}

def verb-submit [device: string, local: bool, text: string]: nothing -> record {
    let limits = limits-load
    let reason = admit $device submit $local
    if $reason != null { fail $"refused: ($reason)" }
    let parsed = try { $text | from json } catch { fail "the job is no JSON" }
    let spec = spec-validate $parsed $limits
    if (units-active | length) >= $RUNNING_MAX { fail "refused: a job is running" }
    let jobs = jobs-dir
    mkdir $jobs
    let header = header-validate (header-read) $spec
    let pin = image-pin $spec.toolchain.oci
    if $header.image == 0 and $pin != null and not (image-exists (image-hex $pin)) {
        fail $"refused: image ($spec.toolchain.oci) is not on this worker; stream it"
    }
    let free = ^df --output=avail --block-size=1 $jobs | lines | last | str trim | into int
    if $free < $DISK_MIN + $header.image + $header.pack { fail "refused: too little free disk" }
    let id = job-id $device (date now) (random binary $NONCE_BYTES | encode hex --lower)
    let dir = $jobs | path join $id
    mkdir $dir
    try {
        if $header.image > 0 { stdin-take ($dir | path join $IMAGE_FILE) $header.image "image archive" }
        stdin-take ($dir | path join $PACK_FILE) $header.pack pack
    } catch {|e|
        rm --recursive --force $dir
        fail $e.msg
    }
    let job = {
        job: $id, client: $device, slug: ($spec.repo | str replace --all --regex '[^A-Za-z0-9._-]+' '-')
        kind: $spec.kind, commit: $spec.commit, command: $spec.command, worktree: ($dir | path join $SOURCE_DIR)
        started: (date now), spec: $spec, shallow: $header.shallow
    }
    $job | to nuon | save ($dir | path join $JOB_FILE)
    let log = $dir | path join $LOG_FILE
    touch $log
    let props = [
        $"MemoryMax=($spec.memoryMiB)M" "MemorySwapMax=0" $"CPUQuota=($spec.cpus * 100 | math round)%"
        $"IOWeight=($IO_WEIGHT)" $"Nice=($NICE)" $"RuntimeMaxSec=($spec.timeoutS + $RUNTIME_MARGIN_S)"
        $"TasksMax=($TASKS_MAX)" $"StandardOutput=append:($log)" $"StandardError=append:($log)"
    ]
    with-env (manager-env) {
        (^systemd-run --user --quiet --collect $"--unit=(unit-name $id)" $"--slice=($SLICE)"
            $"--description=offload ($id)" $"--working-directory=($dir)" ...($props | each { $"--property=($in)" })
            $nu.current-exe --no-config-file $SELF run $id)
    }
    metrics-update
    {id: $id}
}

def verb-status [device: string, local: bool, id: string]: nothing -> record {
    let job = job-load $id $device $local
    job-state (job-dir $id) (units-active) | insert kind $job.kind | insert submitted ($job.started | format date "%+")
}

def verb-get [device: string, local: bool, id: string]: nothing -> nothing {
    job-load $id $device $local | ignore
    let result = job-dir $id | path join $RESULT
    if not ($result | path exists) { fail $"($id) has no result" }
    ^cat $result
}

def verb-cancel [device: string, local: bool, id: string]: nothing -> record {
    job-load $id $device $local | ignore
    job-cancel (job-dir $id) $"cancelled by ($device)"
    metrics-update
    job-state (job-dir $id) (units-active)
}

# Removes this caller's finished oci jobs older than GC_AGE, the images the worker used but not for IMAGE_UNUSED, and
# the least recently used cache entries past CACHE_TOTAL_MAX.
def verb-gc [device: string, local: bool]: nothing -> record {
    let jobs = jobs-dir
    if not ($jobs | path exists) { return {removed: []} }
    let active = units-active
    let cutoff = (date now) - $GC_AGE
    let removed = ls $jobs | where type == dir | get name | where {|d|
        let job = try { open ($d | path join $JOB_FILE) } catch { return false }
        let state = job-state $d $active
        ($job.kind? in $OCI_KINDS and ($local or $job.client? == $device) and $state.state != "running"
            and (ls --directory $d | get 0.modified) < $cutoff)
    } | each {|d|
        do { ^podman unshare rm --recursive --force $d } | complete | ignore
        $d | path basename
    }
    {removed: $removed, images: (images-gc), cache: (cache-trim 0 null)}
}

# Every answer is one JSON line on stdout but get's, which is the result tar; a refusal is {error} and exit 1.
def dispatch [device: string, original: string, local: bool]: nothing -> nothing {
    let result = try {
        if not ($device =~ $DEVICE) { fail "no device name" }
        let command = command-parse $original
        match $command.verb {
            "offer" => { verb-offer $device $local }
            "submit" => { verb-submit $device $local $command.arg }
            "status" => { verb-status $device $local $command.arg }
            "get" => { verb-get $device $local $command.arg; null }
            "cancel" => { verb-cancel $device $local $command.arg }
            "gc" => { verb-gc $device $local }
        }
    } catch {|e| {error: $e.msg} }
    if $result == null { return }
    print ($result | to json --raw)
    if $result.error? != null { exit 1 }
}

# A shallow checkout of exactly the commit from its pack: index-pack checks each object and fails on a thin pack's
# absent delta bases; the commit itself and the parents the header names become the shallow boundary, and the walk of
# the commit's objects then proves its whole tree is there. git's hashing makes the checked out commit the pinned one.
def checkout [dir: path, commit: string, shallow: list<string>]: nothing -> path {
    let src = $dir | path join $SOURCE_DIR
    let pack = $dir | path join $PACK_FILE
    let git = {GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0"}
    with-env $git {
        ^git init --quiet $src
        let indexed = do { ^sh -c 'exec git -C "$1" index-pack --stdin --fsck-objects < "$2"' sh $src $pack } | complete
        if $indexed.exit_code != 0 { fail $"the pack is not the commit's complete closure: ($indexed.stderr | str trim)" }
        if (do { ^git -C $src cat-file -e $"($commit)^{commit}" } | complete).exit_code != 0 {
            fail $"the pack lacks ($commit)"
        }
        [$commit ...$shallow] | uniq | to text | save --force ($src | path join .git shallow)
        if (do { ^git -C $src rev-list --objects --quiet $commit } | complete).exit_code != 0 {
            fail "the pack is not the commit's complete closure: objects of its tree are missing"
        }
        ^git -C $src -c core.hooksPath=/dev/null -c advice.detachedHead=false checkout --quiet --detach $commit
    }
    rm --force $pack
    $src
}

def stamp-dir []: nothing -> path { jobs-dir | path dirname | path join images }

# Marks the image used now, for images-gc; the worker never removes an image it has no stamp of.
def image-stamp [hex: string]: nothing -> nothing {
    mkdir (stamp-dir)
    "" | save --force (stamp-dir | path join $hex)
}

# The streamed archive's one image, its config hashed before podman sees it, then loaded, checked again by id and
# stripped of the names it brought; a mismatch removes whatever it loaded.
def image-load [archive: path, id: string]: nothing -> nothing {
    let manifest = try { ^tar --extract --to-stdout --file $archive -- manifest.json | from json } catch {
        fail "the image is no docker-archive (no manifest.json)"
    }
    if ($manifest | describe) !~ '^(list|table)' or ($manifest | length) != 1 { fail "the image archive holds not exactly one image" }
    let config = $manifest.0.Config?
    if not (is-string $config) or not ($config =~ $ARCHIVE_CONFIG) { fail "the image archive's config member is malformed" }
    let digest = ^tar --extract --to-stdout --file $archive -- $config | ^sha256sum | split row " " | first
    if $"sha256:($digest)" != $id { fail $"the streamed image is sha256:($digest), not the pinned ($id)" }
    let loaded = do { ^podman load --quiet --input $archive } | complete
    rm --force $archive
    let hex = image-hex $id
    if $loaded.exit_code != 0 or not (image-exists $hex) {
        let names = $loaded.stdout | parse --regex '(?m)^Loaded image(?:\(s\))?: (?<ref>\S+)$' | get ref
        for ref in $names { do { ^podman rmi --force $ref } | complete | ignore }
        fail $"loading the image did not give ($id)"
    }
    do { ^podman untag $hex } | complete | ignore
    image-stamp $hex
}

# The id the job runs by: a pinned id as it is (streamed or held, a localhost name never resolved), a registry digest
# pulled if absent, then resolved.
def image-resolve [ref: string]: nothing -> string {
    let pin = image-pin $ref
    if $pin != null {
        if not (image-exists (image-hex $pin)) { fail $"image ($pin) is not on this worker" }
        return (image-hex $pin)
    }
    if not (image-exists $ref) { ^podman pull --quiet $ref | ignore }
    ^podman image inspect --format "{{.Id}}" $ref | str trim | image-hex $in
}

def images-gc []: nothing -> list<string> {
    let dir = stamp-dir
    if not ($dir | path exists) { return [] }
    let cutoff = (date now) - $IMAGE_UNUSED
    ls $dir | where modified < $cutoff | get name | each {|stamp|
        let hex = $stamp | path basename
        let removed = (do { ^podman rmi $hex } | complete).exit_code == 0 or not (image-exists $hex)
        if $removed { rm --force $stamp; $"sha256:($hex)" }
    } | compact
}

def cache-root []: nothing -> path {
    $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join offload
}

def tree-bytes [path: path]: nothing -> int {
    let got = do { ^podman unshare du --summarize --bytes -- $path } | complete
    if $got.exit_code != 0 { return 0 }
    $got.stdout | split row "\t" | first | into int
}

def cache-entries []: nothing -> list<record> {
    let root = cache-root
    if not ($root | path exists) { return [] }
    ls $root | where type == dir and ($it.name | path basename) =~ '^[0-9a-f]{64}$' | each {|d|
        let used = try { ls ($d.name | path join $CACHE_USED) | get 0.modified } catch { $d.modified }
        {key: ($d.name | path basename), bytes: (tree-bytes $d.name), used: $used}
    }
}

# Evicts least recently used entries until the rest and incoming bytes fit CACHE_TOTAL_MAX; the evicted keys.
def cache-trim [incoming: int, keep: any]: nothing -> list<string> {
    let root = cache-root
    # a save cut off midway leaves its hidden staging dir
    if ($root | path exists) {
        ls --all $root | where type == dir and ($it.name | path basename | str starts-with ".") and modified < ((date now) - 1day)
        | each { do { ^podman unshare rm --recursive --force -- $in.name } | complete | ignore } | ignore
    }
    let evict = cache-evict (cache-entries) $CACHE_TOTAL_MAX $incoming $keep
    for key in $evict { do { ^podman unshare rm --recursive --force -- (cache-root | path join $key) } | complete | ignore }
    $evict
}

# Whether any symlink under path resolves outside root: a cached path never carries one out of the checkout.
def links-escape [root: path, path: path]: nothing -> bool {
    let real = ^realpath -- $root | str trim
    let got = do { ^podman unshare find $path -type l -exec realpath --canonicalize-missing -- "{}" + } | complete
    if $got.exit_code != 0 { return true }
    $got.stdout | lines | where $it != "" | any { not (target-inside $real $in) }
}

def tracked [src: path, path: string]: nothing -> bool {
    (^git --literal-pathspecs -C $src ls-files -- $path | str trim | is-not-empty)
}

# Restores the key's cached paths into the fresh checkout: only where nothing is yet, never through a link out of the
# checkout, and dropped again when the restored tree carries a link out.
def cache-restore [src: path, key: string, paths: list<string>]: nothing -> nothing {
    let entry = cache-root | path join $key
    if not ($entry | path exists) { return }
    for p in $paths {
        let cached = $entry | path join $CACHE_TREE $p
        if not ($cached | path exists --no-symlink) { continue }
        let dest = $src | path join $p
        let target = ^realpath --canonicalize-missing -- $dest | str trim
        if not (target-inside (^realpath -- $src | str trim) $target) or ($dest | path exists --no-symlink) or (tracked $src $p) {
            print --stderr $"offload worker: cache ($p) not restored: tracked, present or through a link out"
            continue
        }
        mkdir ($dest | path dirname)
        ^podman unshare cp --archive --reflink=auto -- $cached $dest
        if (links-escape $src $dest) {
            print --stderr $"offload worker: cache ($p) carried a link out of the checkout; dropped"
            do { ^podman unshare rm --recursive --force -- $dest } | complete | ignore
        }
    }
    "" | save --force ($entry | path join $CACHE_USED)
}

# Saves the paths after a job that exited 0: each inside the checkout and untracked, none with a link out, together
# at most CACHE_KEY_MAX; older entries make room first. A path the job did not leave is left out.
def cache-save [src: path, key: string, paths: list<string>]: nothing -> nothing {
    let kept = $paths | where {|p| (inside $src $p) != null and not (tracked $src $p) }
    if ($kept | is-empty) { return }
    if ($kept | any {|p| links-escape $src ($src | path join $p) }) {
        print --stderr "offload worker: cache not saved: a path holds a link out of the checkout"
        return
    }
    let bytes = $kept | reduce --fold 0 {|p, acc| $acc + (tree-bytes ($src | path join $p)) }
    if $bytes > $CACHE_KEY_MAX { print --stderr $"offload worker: cache not saved: ($bytes) bytes over ($CACHE_KEY_MAX)"; return }
    cache-trim $bytes $key | ignore
    let root = cache-root
    mkdir $root
    let entry = $root | path join $key
    let fresh = $root | path join $".($key).(random binary $NONCE_BYTES | encode hex --lower)"
    for p in $kept {
        let dest = $fresh | path join $CACHE_TREE $p
        mkdir ($dest | path dirname)
        ^podman unshare cp --archive --reflink=auto -- ($src | path join $p) $dest
    }
    "" | save --force ($fresh | path join $CACHE_USED)
    if ($entry | path exists) { do { ^podman unshare rm --recursive --force -- $entry } | complete | ignore }
    ^mv $fresh $entry
}

# path below root after symlinks, or null when it leaves root or does not exist; in podman's user namespace, where
# the container's uids own their files
def inside [root: path, path: string]: nothing -> any {
    let real = do { ^podman unshare realpath -e -- ($root | path join $path) } | complete
    if $real.exit_code != 0 { return null }
    let real = $real.stdout | str trim
    if (target-inside (^realpath -- $root | str trim) $real) { $real }
}

# The peak memory of the calling unit's cgroup, its processes and containers together.
export def peak-mib []: nothing -> int {
    let cgroup = open /proc/self/cgroup | lines | where ($it | str starts-with "0::") | get --optional 0 | default "0::/"
        | str substring 3..
    try { open --raw $"/sys/fs/cgroup($cgroup)/memory.peak" | str trim | into int | $in // 1048576 } catch { 0 }
}

def podman-argv [job: record, src: path, image: string]: nothing -> list<string> {
    let spec = $job.spec
    let workdir = if $spec.workdir == "." { $SANDBOX } else { $SANDBOX | path join $spec.workdir }
    [
        --runtime=crun --cgroup-manager=cgroupfs run --rm --cgroups=disabled --pull=never --log-driver=passthrough
        $"--name=(unit-name $job.job | str replace '.service' '')"
        $"--network=(if $spec.network { 'pasta' } else { 'none' })"
        --read-only --security-opt=no-new-privileges --env=HOME=/tmp $"--timeout=($spec.timeoutS)"
        $"--mount=type=bind,src=($src),dst=($SANDBOX)" $"--workdir=($workdir)"
        $image ...$spec.command
    ]
}

# The unit's command: checks the source out, loads or resolves the pinned image, restores the cache, runs the job's
# argv in the image by its id, packs the output and the manifest into the result tar and, after an exit 0, saves the
# cache; the checkout goes, the result stays until gc.
def "main run" [id: string]: nothing -> nothing {
    let dir = job-dir $id
    let job = open ($dir | path join $JOB_FILE)
    let started = date now
    let cache = $job.spec.cache?.paths?
    let attempt = try {
        let src = checkout $dir $job.commit ($job.shallow? | default [])
        if (inside $src $job.spec.workdir) == null { fail $"workdir ($job.spec.workdir) is not inside the checkout" }
        let archive = $dir | path join $IMAGE_FILE
        if ($archive | path exists) { image-load $archive (image-pin $job.spec.toolchain.oci) }
        let image = image-resolve $job.spec.toolchain.oci
        image-stamp $image
        let key = if $cache != null { cache-key $job.client $job.spec.repo $"sha256:($image)" }
        if $key != null {
            let bad = $cache | where { tracked $src $in }
            if ($bad | is-not-empty) { fail $"cache paths ($bad | str join ', ') are tracked" }
            cache-restore $src $key $cache
        }
        let code = try { ^podman ...(podman-argv $job $src $image); 0 } catch { [$env.LAST_EXIT_CODE 1] | math max }
        {code: $code, key: $key}
    } catch {|e|
        print --stderr $"offload worker: ($e.msg)"
        $e.msg | save --force ($dir | path join $ERROR_FILE)
        {code: 1, key: null}
    }
    let code = $attempt.code
    let ended = date now
    let src = $dir | path join $SOURCE_DIR
    let output = if $code == 0 and ($src | path exists) { inside $src $job.spec.output }
    # the container's other uids own part of the output: packed and removed inside podman's user namespace
    let sha = if $output != null {
        try {
            ^podman unshare tar --create --zstd --file ($dir | path join $ARTIFACT) --directory $src -- $job.spec.output
            ^sha256sum ($dir | path join $ARTIFACT) | split row " " | first
        } catch { null }
    }
    if $code == 0 and $sha == null {
        let msg = $"output ($job.spec.output) is missing, outside the checkout or unreadable"
        print --stderr $"offload worker: ($msg)"
        $msg | save --force ($dir | path join $ERROR_FILE)
    }
    let exit = if $code == 0 and $sha == null { 1 } else { $code }
    let peak = peak-mib
    let version = open --raw $SELF | hash sha256 | str substring 0..<12
    let run = {started: $started, ended: $ended, exit: $exit, peakMiB: $peak, sha256: $sha}
    manifest-build $job $run {host: (sys host | get hostname), version: $version} | to json --indent 2
    | save --force ($dir | path join $MANIFEST)
    if $exit == 0 and $attempt.key != null {
        try { cache-save $src $attempt.key $cache } catch {|e| print --stderr $"offload worker: cache not saved: ($e.msg)" }
    }
    let members = [$MANIFEST] ++ (if $sha != null { [$ARTIFACT] } else { [] })
    ^tar --create --file ($dir | path join $RESULT) --directory $dir -- ...$members
    if ($src | path exists) { do { ^podman unshare rm --recursive --force $src } | complete | ignore }
    rm --force ($dir | path join $ARTIFACT)
    $exit | into string | save --force ($dir | path join $EXIT_FILE)
    let seconds = ($ended - $started) / 1sec | math round
    metrics-update {kind: $job.kind, exit: $exit, seconds: $seconds, peakMiB: $peak, ended: (($ended | into int) // 1_000_000_000)}
    exit $exit
}

# Run by offload-enforce.path when a login's gate state changed: while the desktop is busy every running job of this
# user's manager is cancelled; a client sees it cancelled and retries later.
def "main enforce" []: nothing -> nothing {
    let reasons = gate-now
    if ($reasons | is-empty) { return }
    for id in (units-active) {
        job-cancel (jobs-dir | path join $id) $"desktop busy: ($reasons | str join '; ')"
    }
    metrics-update
}

# The forced command of a device's key: its original command is the request, nothing else of ssh's.
def "main serve" [device: string]: nothing -> nothing {
    hide-env --ignore-errors OFFLOAD_ROOT
    dispatch $device ($env.SSH_ORIGINAL_COMMAND? | default "") false
}

# A client running as the caller's own user (offload worker): this desktop itself needs no consent.
def "main local" [device: string, command: string]: nothing -> nothing {
    let here = $device == (sys host | get hostname) and $env.SSH_CONNECTION? == null
    dispatch $device $command $here
}

def main []: nothing -> nothing {
    print --stderr "usage: worker.nu serve <device> | local <device> <command> | run <id> | enforce"
    exit 2
}
