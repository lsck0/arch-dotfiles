#!/usr/bin/env -S nu --no-config-file --stdin
# Runs work on the offload target (the desktop) from a client (the notebook): the repo's HEAD plus its working changes
# travel as a git ref into a bare repo per client there, the command runs in a transient user unit under a sleep
# inhibitor and streams its output back; a disconnect only detaches. On the target the same verbs act locally.
# `offload host <verb>` is the target's half: a client calls it over ssh with fixed, quoted arguments and passes
# anything user-given (the command, paths) as nuon on stdin, so nothing reaches the remote shell unquoted.

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext]
use ($REPO | path join scripts lib state.nu) [xdg file-trim]
use ($REPO | path join scripts lib usage.nu) [die]
use ($REPO | path join configs programming offload worker.nu) [admit job-cancel metrics-update peak-mib]
use ($REPO | path join configs programming offload consent.nu) [trust-list trust-revoke]

export const OFFLOAD_ROLE_TARGET = "target"
export const OFFLOAD_ROLE_CLIENT = "client"
export const OFFLOAD_ROLES = [$OFFLOAD_ROLE_TARGET $OFFLOAD_ROLE_CLIENT]

const CONFIG = [offload config.nuon]
const HOME_NETWORK = "/run/home-network"
const WG_IFACE = "wg0"
const LOOPBACK = "127.0.0.1"
const PROBE_TIMEOUT_S = 2
const PROBE_TRIES = 2
const WAKE_TRIES = 45
const WAKE_INTERVAL = 2sec
const ROUTER_TIMEOUT_S = 5
const CONTROL_PERSIST_S = 60
const SERVER_ALIVE_S = 15

# relative to the target's home, where an ssh command starts
const TARGET_COMMAND = ".local/bin/offload"
const HERDR_OPEN = ".local/bin/herdr-open"
const HERDR_POLLS = 100
const HERDR_POLL_INTERVAL = 100ms
# the worker's protocol entry, installed by the system verb on the target
const WORKER = "/usr/local/lib/offload/worker.nu"
const SLICE = "offload.slice"
const NICE = 10
const IO_WEIGHT = 10
const UNIT_PREFIX = "offload-"
const REF_PREFIX = "refs/offload"
const JOB_FILE = "job.nuon"
const LOG_FILE = "log"
const EXIT_FILE = "exit"
# finished jobs kept on the target with their logs and refs; older ones go when a new one starts
const JOBS_KEPT = 50
const KIND_RUN = "run"
const KIND_AGENT = "agent"
const KINDS = [$KIND_RUN $KIND_AGENT]
const AGENT_SUFFIX = ".agent"
const NAME_MAX = 40
const NAME_FALLBACK = "repo"
const JOB_ID_MAX = 64
const JOB_ID = '^[a-z0-9][a-z0-9._-]*$'
const COMMIT = '^[0-9a-f]{40}([0-9a-f]{24})?$'
const TARGET_PATH = '^/[A-Za-z0-9._/-]+$'
const STAMP_FORMAT = "%m%d-%H%M%S"
const NONCE_BYTES = 2
const SNAPSHOT_MESSAGE = "offload snapshot"
const SNAPSHOT_IDENTITY = {
    GIT_AUTHOR_NAME: offload, GIT_AUTHOR_EMAIL: "offload@localhost"
    GIT_COMMITTER_NAME: offload, GIT_COMMITTER_EMAIL: "offload@localhost"
}
const EXIT_NOT_FOUND = 127
const USAGE = "usage: offload [--untracked] [--detach] [--] <command...>
       offload attach|stop|fetch <job> [paths...]
       offload ls | status | agent [--untracked] | forward <service> [--port <n>]
       offload worker <device> '<verb> [arg]' | trust [--json] | trust revoke <device>"

# The leading flags of a run, up to the command or a `--`.
export def args-parse [argv: list<string>]: nothing -> record<untracked: bool, detach: bool, command: list<string>> {
    mut untracked = false
    mut detach = false
    mut rest = $argv
    while ($rest | is-not-empty) {
        let arg = $rest | first
        if $arg == "--" {
            $rest = $rest | skip 1
            break
        }
        if not ($arg | str starts-with "-") { break }
        match $arg {
            "--untracked" | "-u" => { $untracked = true }
            "--detach" | "-d" => { $detach = true }
            _ => { error make {msg: $"unknown flag ($arg); a command starting with - goes after --"} }
        }
        $rest = $rest | skip 1
    }
    if ($rest | is-empty) { error make {msg: "no command"} }
    {untracked: $untracked, detach: $detach, command: $rest}
}

# A host or repo name as a unit, ref and path part: lowercase, runs of anything else one dash.
export def name-safe [name: string]: nothing -> string {
    let safe = $name | str lowercase | str replace --all --regex '[^a-z0-9._-]+' '-' | str replace --regex '^[._-]+' ''
        | str substring 0..<$NAME_MAX | str replace --regex '[._-]+$' ''
    if $safe == "" { $NAME_FALLBACK } else { $safe }
}

# The nonce keeps two jobs of one repo started in the same second apart.
export def job-id [slug: string, time: datetime, nonce: string]: nothing -> string {
    $"($slug)-($time | format date $STAMP_FORMAT)-($nonce)"
}

export def job-id-valid [job: string]: nothing -> bool {
    $job =~ $JOB_ID and not ($job | str contains "..") and ($job | str length) <= $JOB_ID_MAX
}

export def ref-source [job: string]: nothing -> string { $"($REF_PREFIX)/($job)/source" }
export def ref-result [job: string]: nothing -> string { $"($REF_PREFIX)/($job)/result" }
export def unit-name [job: string]: nothing -> string { $"($UNIT_PREFIX)($job).service" }

export def sh-quote [arg: string]: nothing -> string {
    $"'($arg | str replace --all "'" "'\\''")'"
}

# The command line ssh hands the target's login shell: every word quoted.
export def remote-command [argv: list<string>]: nothing -> string {
    $argv | each { sh-quote $in } | str join " "
}

export def ssh-options [config: record, control: string, identities: list<path>]: nothing -> list<string> {
    let ids = $identities | each { [-i $in] } | flatten
    let only = if ($identities | is-empty) { [] } else { [-o IdentitiesOnly=yes] }
    [
        -p ($config.port | into string) -o ControlMaster=auto -o $"ControlPath=($control)"
        -o $"ControlPersist=($CONTROL_PERSIST_S)" -o $"ServerAliveInterval=($SERVER_ALIVE_S)" ...$ids ...$only
    ]
}

# Why the target is out of reach from here, or null when home or the tunnel routes its lan address.
export def reach-blocker [at_home: bool, wg_up: bool, route_dev: string]: nothing -> any {
    if $at_home { return null }
    if not $wg_up { return $"away from home and ($WG_IFACE) is down; bring the home vpn up first \(bar: network, Home VPN\)" }
    if $route_dev != $WG_IFACE {
        return $"the target's address routes out ($route_dev), not ($WG_IFACE): this network shadows the home lan"
    }
    null
}

# The router address that sends the wake packet: the lan one at home, the tunnel one away, null when none fits.
export def router-address [config: record, at_home: bool, route_dev: string]: nothing -> any {
    if $config.router == null { return null }
    if $at_home { return $config.router }
    if $config.router_tunnel != null { return $config.router_tunnel }
    if $route_dev == $WG_IFACE { return $config.router }
    null
}

export def forward-spec [config: record, service: string, port_local?: int]: nothing -> string {
    let port = $config.forwards | get --optional $service
    if $port == null {
        error make {msg: $"no service ($service); one of ($config.forwards | columns | str join ', ')"}
    }
    $"($LOOPBACK):($port_local | default $port):($LOOPBACK):($port)"
}

export def path-relative-valid [path: string]: nothing -> bool {
    $path != "" and not ($path | str starts-with "/") and ($path | path split | all { $in != ".." })
}

# A request the target acts on, checked whole: names as name-safe makes them, a job id, a full commit id.
export def request-valid [request: record]: nothing -> bool {
    let names = [$request.client? $request.slug?] | all {|n| ($n | describe) == string and (name-safe $n) == $n }
    let command = $request.command? | default []
    ($names and (job-id-valid ($request.job? | default "")) and $request.kind? in $KINDS
        and ($request.commit? | default "") =~ $COMMIT and ($command | describe) =~ '^list'
        and ($command | all { ($in | describe) == string })
        and (($request.kind == $KIND_AGENT) or ($command | is-not-empty)))
}

def config-load []: nothing -> record {
    let file = xdg config ...$CONFIG
    if not ($file | path exists) { die $"no ($file): this machine has no offload role \(platform fact offload\)" }
    let config = open $file
    if $config.role? not-in $OFFLOAD_ROLES { die $"($file): role is not one of ($OFFLOAD_ROLES | str join ', ')" }
    $config
}

def repo-top []: nothing -> path {
    let top = do { ^git rev-parse --show-toplevel } | complete
    if $top.exit_code != 0 { die "not inside a git repo; offload sends the repo's state" }
    if (do { ^git rev-parse --verify --quiet HEAD } | complete).exit_code != 0 { die "the repo has no commit yet" }
    $top.stdout | str trim
}

# HEAD plus the working tree as one commit on top of it, through a scratch index: HEAD, the index and the worktree
# stay as they are. Tracked and staged files always, untracked files (ignored ones never) only with all.
def snapshot-create [top: path, all: bool]: nothing -> string {
    let dir = mktemp --directory --tmpdir offload-XXXXXX
    let index = ^git -C $top rev-parse --path-format=absolute --git-path index | str trim
    let scratch = $dir | path join index
    if ($index | path exists) { cp $index $scratch }
    let tree = with-env {GIT_INDEX_FILE: $scratch} {
        if not ($scratch | path exists) { ^git -C $top read-tree HEAD }
        ^git -C $top add (if $all { "--all" } else { "--update" })
        ^git -C $top write-tree | str trim
    }
    rm --recursive $dir
    let commit = with-env $SNAPSHOT_IDENTITY {
        ^git -C $top commit-tree --no-gpg-sign -p HEAD -m $SNAPSHOT_MESSAGE $tree | str trim
    }
    if not ($commit =~ $COMMIT) { error make {msg: $"offload: commit-tree gave '($commit)'"} }
    $commit
}

def self-argv []: nothing -> list<string> {
    [$nu.current-exe --no-config-file --stdin $env.CURRENT_FILE]
}

def at-home []: nothing -> bool {
    ($HOME_NETWORK | path exists) and (open --raw $HOME_NETWORK | lines | where $it != "" | is-not-empty)
}

def wg-up []: nothing -> bool { $"/sys/class/net/($WG_IFACE)" | path exists }

def route-dev [address: string]: nothing -> string {
    do { ^ip -o route get $address } | complete | get stdout | parse --regex 'dev (?<dev>\S+)' | get --optional 0.dev
    | default ""
}

def identities []: nothing -> list<path> {
    [($REPO | path join configs secrets keys ssh private.asc) ($nu.home-dir | path join .ssh id_ed25519_sk)]
    | where { secret-is-plaintext $in }
}

def ssh-base [config: record]: nothing -> list<string> {
    ssh-options $config (xdg runtime "offload-%C") (identities)
}

def master-alive [config: record]: nothing -> bool {
    (do { ^ssh ...(ssh-base $config) -O check $config.host } | complete).exit_code == 0
}

# Knocks (base/nftables), then probes the hidden sshd port; the knock only opens it once the target's firewall is up.
def knock-open [config: record, tries: int]: nothing -> bool {
    for _ in 1..$tries {
        ^knock $config.host ...($config.knock | each { into string })
        let probe = do { ^nc -z -w $PROBE_TIMEOUT_S $config.host ($config.port | into string) } | complete
        if $probe.exit_code == 0 { return true }
    }
    false
}

# Reachable, or woken through the homelab router's wol-pc (base/ssh.wake_router) and waited for; the first ssh after
# this opens the shared connection inside the knock window, every later one rides it.
def connect [config: record]: nothing -> nothing {
    if $config.role == $OFFLOAD_ROLE_TARGET or (master-alive $config) or (knock-open $config $PROBE_TRIES) { return }
    let home = at-home
    let blocker = reach-blocker $home (wg-up) (route-dev $config.host)
    if $blocker != null { die $blocker }
    let router_dev = if $config.router != null { route-dev $config.router } else { "" }
    let router = router-address $config $home $router_dev
    if $router == null { die $"($config.host) does not answer and no router can wake it \(base/ssh.wake_router\)" }
    # the tunnel address checks against the router's lan host key, as wake-pc does
    let key = [-o $"HostKeyAlias=($config.router)" -o $"UserKnownHostsFile=($nu.home-dir)/.ssh/known_hosts.homelab"]
    print --stderr $"offload: waking ($config.host) ..."
    let sent = do { ^ssh -o $"ConnectTimeout=($ROUTER_TIMEOUT_S)" ...$key $"root@($router)" wol-pc } | complete
    if $sent.exit_code != 0 { die $"the router at ($router) did not send the magic packet" }
    for _ in 1..$WAKE_TRIES {
        if (knock-open $config 1) { return }
        sleep $WAKE_INTERVAL
    }
    die $"($config.host) did not answer ssh after the wake"
}

# `offload host <verb> ...args` on the target with input as nuon on stdin; its stdout parsed as nuon.
def host-call [config: record, verb: string, args: list<string>, input: any = null]: nothing -> any {
    let argv = [host $verb ...$args]
    let stdin = $input | to nuon
    let run = if $config.role == $OFFLOAD_ROLE_TARGET {
        let self = self-argv
        $stdin | do { ^($self | first) ...($self | skip 1) ...$argv } | complete
    } else {
        $stdin | do { ^ssh ...(ssh-base $config) $config.host (remote-command [$TARGET_COMMAND ...$argv]) } | complete
    }
    if $run.exit_code != 0 {
        print --stderr --no-newline $run.stderr
        exit $run.exit_code
    }
    $run.stdout | from nuon
}

# The same, handing the terminal over (attach, agent).
def host-exec [config: record, verb: string, args: list<string>, --tty]: nothing -> nothing {
    let argv = [host $verb ...$args]
    if $config.role == $OFFLOAD_ROLE_TARGET {
        let self = self-argv
        exec ($self | first) ...($self | skip 1) ...$argv
    }
    let tty = if $tty { [-t] } else { [] }
    exec ssh ...(ssh-base $config) ...$tty $config.host (remote-command [$TARGET_COMMAND ...$argv])
}

# The url and environment git pushes and fetches to the target's bare repo with: a path on the target itself, ssh
# over the shared connection from a client.
def git-remote [config: record, bare: string]: nothing -> record<url: string, env: record> {
    if not ($bare =~ $TARGET_PATH) { die $"the target reported the repo path '($bare)'" }
    if $config.role == $OFFLOAD_ROLE_TARGET { return {url: $bare, env: {}} }
    {url: $"($config.host):($bare)", env: {GIT_SSH_COMMAND: (remote-command [ssh ...(ssh-base $config)]), GIT_SSH_VARIANT: ssh}}
}

def job-arg [job: string]: nothing -> string {
    if not (job-id-valid $job) { die --misuse $"'($job)' is no job id \(offload ls\)" }
    $job
}

# Snapshot, wake, push and start: the job's record as the target wrote it.
def job-send [config: record, kind: string, untracked: bool, command: list<string>]: nothing -> record {
    let top = repo-top
    let slug = name-safe ($top | path basename)
    let client = name-safe (sys host | get hostname)
    let commit = snapshot-create $top $untracked
    connect $config
    let job = job-id $slug (date now) (random binary $NONCE_BYTES | encode hex --lower)
    let bare = (host-call $config init [$client $slug]).bare
    let remote = git-remote $config $bare
    with-env $remote.env { ^git -C $top push --no-verify --quiet $remote.url $"($commit):(ref-source $job)" }
    let request = {job: $job, client: $client, slug: $slug, kind: $kind, commit: $commit, command: $command}
    let started = host-call $config start [] $request
    if $started.note? != null { print --stderr $"offload: ($started.note)" }
    $started
}

def offload-dir [...parts: string]: nothing -> path { xdg state offload ...$parts }
def bare-path [client: string, slug: string]: nothing -> path { offload-dir repos $client $"($slug).git" }

def worktree-path [client: string, slug: string, kind: string]: nothing -> path {
    offload-dir repos $client (if $kind == $KIND_AGENT { $"($slug)($AGENT_SUFFIX)" } else { $slug })
}

def job-dir [job: string]: nothing -> path {
    let dir = offload-dir jobs (job-arg $job)
    if not ($dir | path join $JOB_FILE | path exists) { die $"no job ($job) \(offload ls\)" }
    $dir
}

def units-active []: nothing -> list<string> {
    ^systemctl --user list-units $"($UNIT_PREFIX)*" --state=active,activating --plain --no-legend
    | lines | each { split row " " | first | str replace --regex $'^($UNIT_PREFIX)' '' | str replace --regex '\.service$' '' }
}

def unit-main-pid [job: string]: nothing -> int {
    do { ^systemctl --user show --property=MainPID --value (unit-name $job) } | complete | get stdout | str trim
    | if $in =~ '^\d+$' { into int } else { 0 }
}

def jobs-list []: nothing -> table {
    let dir = offload-dir jobs
    if not ($dir | path exists) { return [] }
    let active = units-active
    ls $dir | where type == dir | get name | where { $in | path join $JOB_FILE | path exists } | each {|d|
        let job = open ($d | path join $JOB_FILE)
        let exit = file-trim ($d | path join $EXIT_FILE) null
        let state = if $job.kind == $KIND_AGENT { $KIND_AGENT } else if $job.job in $active { "running" } else if $exit == null {
            "stopped"
        } else { $"exit ($exit)" }
        {job: $job.job, client: $job.client, repo: $job.slug, state: $state, started: $job.started, worktree: $job.worktree}
    } | sort-by started
}

# A fresh worktree, or the existing one forced to the commit with its untracked files gone (ignored build output
# stays, so builds stay incremental). keep_dirty leaves a worktree with changes alone: an agent's work in progress.
def worktree-checkout [bare: path, worktree: path, commit: string, keep_dirty: bool]: nothing -> any {
    if not ($worktree | path exists) {
        ^git --git-dir $bare worktree prune
        ^git --git-dir $bare worktree add --quiet --detach --force $worktree $commit
        return null
    }
    if $keep_dirty and (^git -C $worktree status --porcelain | str trim | is-not-empty) {
        return $"kept ($worktree) as it is: it has changes, the snapshot was not checked out"
    }
    ^git -C $worktree checkout --quiet --force --detach $commit
    ^git -C $worktree clean -d --force --quiet
    null
}

def jobs-prune []: nothing -> nothing {
    let active = units-active
    let done = jobs-list | where job not-in $active
    if ($done | length) <= $JOBS_KEPT { return }
    $done | first (($done | length) - $JOBS_KEPT) | each {|j|
        let bare = bare-path $j.client $j.repo
        if ($bare | path exists) {
            for ref in [(ref-source $j.job) (ref-result $j.job)] { do { ^git --git-dir $bare update-ref -d $ref } | complete | ignore }
        }
        rm --recursive --force (offload-dir jobs $j.job)
    } | ignore
}

def herdr-server-ensure []: nothing -> nothing {
    let running = { (do { ^herdr status server } | complete | get stdout) =~ "status: running" }
    if (do $running) { return }
    ^setsid -f herdr server out+err> /dev/null
    if not (seq 1 $HERDR_POLLS | any {|_| sleep $HERDR_POLL_INTERVAL; do $running }) { die "the herdr server did not start" }
}

def "main host init" [client: string, slug: string]: nothing -> nothing {
    if (name-safe $client) != $client or (name-safe $slug) != $slug { die --misuse "init: not a client and repo name" }
    let bare = bare-path $client $slug
    if not ($bare | path exists) {
        mkdir ($bare | path dirname)
        ^git init --quiet --bare $bare
    }
    print ({bare: $bare} | to nuon)
}

# Checks the job's commit out and, for a run, starts its unit; the request comes as nuon on stdin.
def "main host start" []: string -> nothing {
    let request = try { $in | from nuon } catch { die --misuse "start: stdin is no nuon" }
    if ($request | describe) !~ '^record' or not (request-valid $request) { die --misuse "start: not a valid request" }
    let bare = bare-path $request.client $request.slug
    if not ($bare | path exists) { die $"no ($bare): init first" }
    # the worker's admission, as for every client: idle desktop, then the device's consent (this desktop needs none)
    let device = $request.client | str replace --all --regex '[._]+' '-'
    let local = $request.client == (name-safe (sys host | get hostname)) and $env.SSH_CONNECTION? == null
    let refused = admit $device $request.kind $local
    if $refused != null { die $"refused: ($refused)" }
    let dir = offload-dir jobs $request.job
    if ($dir | path exists) { die $"job ($request.job) exists already" }
    let worktree = worktree-path $request.client $request.slug $request.kind
    if $request.kind == $KIND_RUN {
        let busy = jobs-list | where state == running and worktree == $worktree
        if ($busy | is-not-empty) { die $"($busy.0.job) still runs in ($worktree): offload attach or stop it" }
    }
    let note = worktree-checkout $bare $worktree $request.commit ($request.kind == $KIND_AGENT)
    mkdir $dir
    $request | insert worktree $worktree | insert started (date now) | to nuon | save ($dir | path join $JOB_FILE)
    if $request.kind == $KIND_RUN {
        let log = $dir | path join $LOG_FILE
        touch $log
        let self = self-argv
        (^systemd-run --user --quiet --collect $"--unit=(unit-name $request.job)" $"--description=offload ($request.job)"
            $"--slice=($SLICE)" $"--property=Nice=($NICE)" $"--property=IOWeight=($IO_WEIGHT)"
            $"--working-directory=($worktree)" $"--property=StandardOutput=append:($log)"
            $"--property=StandardError=append:($log)"
            systemd-inhibit --what=sleep --mode=block --who=offload $"--why=job ($request.job)"
            ...$self host exec $request.job)
    }
    jobs-prune
    print ({job: $request.job, worktree: $worktree, note: $note} | to nuon)
}

# The unit's command: runs the job's argv as it is, no shell, and records its exit code.
def "main host exec" [job: string]: nothing -> nothing {
    let dir = job-dir $job
    let record = open ($dir | path join $JOB_FILE)
    let command = $record.command
    let name = $command | first
    let code = if not ($name | str contains "/") and (which $name | is-empty) {
        print --stderr $"offload: ($name): command not found"
        $EXIT_NOT_FOUND
    } else {
        try { run-external $name ...($command | skip 1); 0 } catch { [$env.LAST_EXIT_CODE 1] | math max }
    }
    $code | into string | save --force ($dir | path join $EXIT_FILE)
    let ended = date now
    let seconds = ($ended - $record.started) / 1sec | math round
    metrics-update {kind: $KIND_RUN, exit: $code, seconds: $seconds, peakMiB: (peak-mib), ended: (($ended | into int) // 1_000_000_000)}
    exit $code
}

# Streams the log from its start until the job ends, then exits with the job's code.
def "main host attach" [job: string]: nothing -> nothing {
    let dir = job-dir $job
    let log = $dir | path join $LOG_FILE
    if not ($log | path exists) { die $"($job) is an agent session: offload agent" }
    let pid = unit-main-pid $job
    if $pid > 0 { ^tail --lines=+1 --follow $"--pid=($pid)" $log } else { ^cat $log }
    let code = file-trim ($dir | path join $EXIT_FILE) null
    if $code == null {
        print --stderr $"offload: ($job) was stopped"
        exit 1
    }
    print --stderr $"offload: ($job) exited ($code)"
    exit ($code | into int)
}

def "main host ls" []: nothing -> nothing { print (jobs-list | to nuon) }

def "main host stop" [job: string]: nothing -> nothing {
    job-cancel (job-dir $job) "stopped by offload stop"
    metrics-update
    print (null | to nuon)
}

# The job's worktree as it is now, committed on top of its HEAD as the job's result ref. A run's worktree is shared
# by the repo's runs, so its HEAD must still be the job's commit; an agent's worktree keeps its work across sessions
# and its own commits.
def "main host snapshot" [job: string]: nothing -> nothing {
    let record = open (job-dir $job | path join $JOB_FILE)
    let head = ^git -C $record.worktree rev-parse HEAD | str trim
    if $record.kind == $KIND_RUN and $head != $record.commit { die $"($record.worktree) moved on to a later job; ($job)'s result is gone" }
    let commit = snapshot-create $record.worktree true
    ^git -C $record.worktree update-ref (ref-result $job) $commit
    print ({ref: (ref-result $job), commit: $commit, bare: (bare-path $record.client $record.slug)} | to nuon)
}

# The listed paths of the job's worktree as a tar stream on stdout; each must stay inside the worktree.
def "main host tar" [job: string]: string -> nothing {
    let paths = $in | from nuon
    let worktree = open (job-dir $job | path join $JOB_FILE) | get worktree
    let root = $worktree | path expand
    for p in $paths {
        let full = $worktree | path join $p
        if not (path-relative-valid $p) or not ($full | path exists) or not ($full | path expand | str starts-with $"($root)/") {
            die $"tar: ($p) is no path inside the job's worktree"
        }
    }
    ^tar --create --directory $worktree -- ...$paths
}

def "main host agent" [job: string]: nothing -> nothing {
    let record = open (job-dir $job | path join $JOB_FILE)
    if $record.kind != $KIND_AGENT { die $"($job) is a run: offload attach" }
    herdr-server-ensure
    ^($nu.home-dir | path join $HERDR_OPEN) $record.worktree $"offload-($record.client)-($record.slug)"
    exec herdr
}

def "main host" []: nothing -> nothing { die --misuse "host verbs are the target's half, called by offload" }

def "main attach" [job: string]: nothing -> nothing {
    let config = config-load
    let job = job-arg $job
    connect $config
    host-exec $config attach [$job]
}

def "main stop" [job: string]: nothing -> nothing {
    let config = config-load
    let job = job-arg $job
    connect $config
    host-call $config stop [$job] | ignore
}

def "main ls" []: nothing -> nothing {
    let config = config-load
    connect $config
    print (host-call $config ls [] | reject worktree)
}

# Without paths: the job's worktree as a result ref fetched into this repo. With paths: those files and dirs of the
# worktree unpacked over this repo's.
def "main fetch" [job: string, ...paths: string]: nothing -> nothing {
    let config = config-load
    let job = job-arg $job
    let top = repo-top
    let bad = $paths | where { not (path-relative-valid $in) }
    if ($bad | is-not-empty) { die --misuse $"not relative paths inside the repo: ($bad | str join ', ')" }
    connect $config
    if ($paths | is-not-empty) {
        let argv = [host tar $job]
        let input = $paths | to nuon
        if $config.role == $OFFLOAD_ROLE_TARGET {
            let self = self-argv
            $input | ^($self | first) ...($self | skip 1) ...$argv | ^tar --extract --directory $top
        } else {
            $input | ^ssh ...(ssh-base $config) $config.host (remote-command [$TARGET_COMMAND ...$argv]) | ^tar --extract --directory $top
        }
        print --stderr $"offload: unpacked ($paths | str join ' ') into ($top)"
        return
    }
    let result = host-call $config snapshot [$job]
    let remote = git-remote $config $result.bare
    with-env $remote.env { ^git -C $top fetch --quiet --no-tags $remote.url $"+($result.ref):($result.ref)" }
    print --stderr $"offload: fetched ($result.ref): git diff HEAD ($result.ref)"
}

# An agent session in a herdr workspace on the target, in a worktree of its own per repo; detach with herdr's own
# key, reattach with offload agent again (a worktree with changes is reopened as it is).
def "main agent" [--untracked]: nothing -> nothing {
    let config = config-load
    let started = job-send $config $KIND_AGENT $untracked []
    host-exec $config agent [$started.job] --tty
}

# A socket-activated model service of the target on this machine's loopback, until ctrl-c.
def "main forward" [service: string, --port: int]: nothing -> nothing {
    let config = config-load
    let spec = try { forward-spec $config $service $port } catch {|e| die --misuse $e.msg }
    if $config.role == $OFFLOAD_ROLE_TARGET {
        die $"($service) is local here: http://($LOOPBACK):($config.forwards | get $service)"
    }
    connect $config
    let local = $spec | split row ":" | get 1
    print --stderr $"offload: ($service) on http://($LOOPBACK):($local) until ctrl-c"
    exec ssh ...(ssh-base $config) -N -L $spec $config.host
}

# The peer's state without waking it: on a client the target's reach and its running jobs, on the target the jobs and
# the clients they came from.
def "main status" []: nothing -> nothing {
    let config = config-load
    let jobs = if $config.role == $OFFLOAD_ROLE_TARGET { jobs-list } else {
        let home = at-home
        let reach = if (master-alive $config) or (knock-open $config 1) { "awake" } else {
            reach-blocker $home (wg-up) (route-dev $config.host) | default "asleep or off"
        }
        print {target: $config.host, network: (if $home { "home" } else if (wg-up) { $WG_IFACE } else { "away" }), reach: $reach}
        if $reach != "awake" { return }
        host-call $config ls []
    }
    let running = $jobs | where state == running
    print {running: ($running | length), jobs: ($jobs | length)}
    if ($running | is-not-empty) { print ($running | reject worktree) }
    if $config.role == $OFFLOAD_ROLE_TARGET and ($jobs | is-not-empty) {
        print ($jobs | group-by client | items {|client, js| {client: $client, last: ($js | last | get started)} })
    }
}

# The worker's protocol (offer, submit, status, get, cancel, gc) as this user, for a script here or a client over
# ssh: the same entry and job spec the lab's builder uses through its forced command.
def "main worker" [device: string, command: string]: nothing -> nothing {
    if not ($WORKER | path exists) { die $"no ($WORKER): the worker runs on the offload target" }
    exec $nu.current-exe --no-config-file $WORKER local $device $command
}

# The devices allowed to offload without asking (offload-consent's Always allow), --json for the bar.
def "main trust" [--json]: nothing -> nothing {
    let devices = trust-list
    print (if $json { $devices | to json --raw } else { $devices })
}

def "main trust revoke" [device: string]: nothing -> nothing {
    try { trust-revoke $device } catch {|e| die --misuse $e.msg }
}

# Runs a command on the target in the repo's current state (HEAD plus tracked changes; --untracked adds untracked
# files): output streams here, ctrl-c or a lost connection only detaches. --detach starts it and returns.
# untyped: a typed rest makes nu parse `true` or `null` as values and refuse them
def --wrapped main [...argv]: nothing -> nothing {
    let parsed = try { args-parse $argv } catch {|e| die --misuse $"($e.msg)\n($USAGE)" }
    let config = config-load
    let started = job-send $config $KIND_RUN $parsed.untracked $parsed.command
    print --stderr $"offload: job ($started.job) in ($started.worktree)"
    if $parsed.detach {
        print $started.job
        return
    }
    host-exec $config attach [$started.job]
}
