#!/usr/bin/env -S nu --no-config-file
# offload's pure parts by table, then whole runs against stubs on PATH (systemd-run runs the unit inline, ssh runs the
# remote command line in a scratch home through sh): the target acting locally, a client over the stubbed ssh, a
# hostile argument staying one literal argument, and the client's repo left exactly as it was.

use offload.nu [
    args-parse name-safe job-id job-id-valid ref-source ref-result sh-quote remote-command reach-blocker router-address
    forward-spec path-relative-valid request-valid
]

const SCRIPT = path self offload.nu
const COMMIT = "0123456789abcdef0123456789abcdef01234567"

def fail [msg: string] { error make {msg: $"offload.test: ($msg)"} }

def pure-check [] {
    let parses = [
        [argv untracked detach command];
        [[make] false false [make]]
        [[-u -d cargo build] true true [cargo build]]
        [[--untracked -- -weird] true false [-weird]]
        [[cargo build --detach] false false [cargo build --detach]]
        [[-- ls -la] false false [ls -la]]
    ]
    for c in $parses {
        let got = args-parse $c.argv
        if $got != ($c | select untracked detach command) { fail $"args-parse ($c.argv | to nuon): ($got | to nuon)" }
    }
    for bad in [[] [-d] [--] [-x make]] {
        if (try { args-parse $bad; true } catch { false }) { fail $"args-parse ($bad | to nuon) passed" }
    }

    let names = [
        [name want];
        [arch-dotfiles arch-dotfiles]
        ["My Repo (old)" my-repo-old]
        [".." repo]
        ["../../etc" etc]
        ["luca-notebook" luca-notebook]
        ["a'b;c" a-b-c]
    ]
    for c in $names { if (name-safe $c.name) != $c.want { fail $"name-safe ($c.name): (name-safe $c.name)" } }

    let job = job-id arch-dotfiles (2026-11-16T14:22:33 | into datetime) 0a1b
    if $job != "arch-dotfiles-1116-142233-0a1b" { fail $"job-id: ($job)" }
    let ids = [
        [job valid];
        [$job true]
        ["a..b" false]
        ["../x" false]
        ["-x" false]
        ["x y" false]
        ["X" false]
        [("a" | fill --width 65 --character a) false]
    ]
    for c in $ids { if (job-id-valid $c.job) != $c.valid { fail $"job-id-valid ($c.job)" } }
    if (ref-source $job) != $"refs/offload/($job)/source" or (ref-result $job) != $"refs/offload/($job)/result" {
        fail "ref names"
    }

    # every word comes back from sh exactly as it went in
    let words = ["plain" "two words" "it's" "$(touch pwned)" "`id`" "a\"b" "back\\slash" "" "'" "*" "~" "x;y|z&"]
    for w in $words {
        let echoed = ^sh -c $"printf %s (sh-quote $w)"
        if $echoed != $w { fail $"sh-quote ($w | to nuon): came back ($echoed | to nuon)" }
    }
    let line = remote-command [.local/bin/offload host start "it's"]
    if $line != "'.local/bin/offload' 'host' 'start' 'it'\\''s'" { fail $"remote-command: ($line)" }

    let blockers = [
        [home wg dev blocked];
        [true false "" false]
        [false false "" true]
        [false true wg0 false]
        [false true wlan0 true]
    ]
    for c in $blockers {
        if ((reach-blocker $c.home $c.wg $c.dev) != null) != $c.blocked { fail $"reach-blocker ($c | to nuon)" }
    }
    let config = {router: "192.168.178.29", router_tunnel: "10.0.0.1"}
    let routers = [
        [config home dev want];
        [$config true "" "192.168.178.29"]
        [$config false wlan0 "10.0.0.1"]
        [($config | update router_tunnel null) false wg0 "192.168.178.29"]
        [($config | update router_tunnel null) false wlan0 null]
        [($config | update router null) true "" null]
    ]
    for c in $routers {
        let got = router-address $c.config $c.home $c.dev
        if $got != $c.want { fail $"router-address ($c | to nuon): ($got)" }
    }

    let forwards = {forwards: {ollama: 11434, vllm: 8000}}
    if (forward-spec $forwards ollama) != "127.0.0.1:11434:127.0.0.1:11434" { fail "forward-spec default port" }
    if (forward-spec $forwards vllm 9000) != "127.0.0.1:9000:127.0.0.1:8000" { fail "forward-spec local port" }
    if (try { forward-spec $forwards sshd; true } catch { false }) { fail "forward-spec took an unknown service" }

    let paths = [
        [path valid];
        [target/release/app true]
        [out.txt true]
        ["" false]
        [/etc/passwd false]
        [../x false]
        [a/../../x false]
    ]
    for c in $paths { if (path-relative-valid $c.path) != $c.valid { fail $"path-relative-valid ($c.path)" } }

    let request = {job: $job, client: luca-notebook, slug: arch-dotfiles, kind: run, commit: $COMMIT, command: [make]}
    let requests = [
        [request valid];
        [$request true]
        [($request | update kind agent | update command []) true]
        [($request | update command []) false]
        [($request | update client "../x") false]
        [($request | update slug "a b") false]
        [($request | update job "../../x") false]
        [($request | update kind shell) false]
        [($request | update commit HEAD) false]
        [($request | update command [make 1]) false]
        [($request | reject commit) false]
    ]
    for c in $requests { if (request-valid $c.request) != $c.valid { fail $"request-valid ($c.request | to nuon)" } }
}

# Stub commands: the unit runs inline with its log redirection, the inhibitor just runs its command, the knock and
# probe always pass, ssh runs the command line through sh in the scratch home (-O check: no shared connection).
def stubs-write [bin: path] {
    mkdir $bin
    let stubs = {
        systemd-run: '#!/bin/sh
dir=.; log=/dev/null
while [ $# -gt 0 ]; do
  case $1 in
    --working-directory=*) dir=${1#*=} ;;
    --property=StandardOutput=append:*) log=${1#*append:} ;;
    --*) ;;
    *) break ;;
  esac
  shift
done
cd "$dir" && "$@" >>"$log" 2>&1
exit 0'
        systemd-inhibit: '#!/bin/sh
while [ $# -gt 0 ]; do case $1 in --*) shift ;; *) break ;; esac; done
exec "$@"'
        systemctl: '#!/bin/sh
case "$*" in *show*) echo 0 ;; esac
exit 0'
        knock: "#!/bin/sh\nexit 0"
        nc: "#!/bin/sh\nexit 0"
        ssh: '#!/bin/sh
while [ $# -gt 0 ]; do
  case $1 in
    -O) exit 1 ;;
    -p|-o|-i|-L) shift 2 ;;
    -t|-N) shift ;;
    *) break ;;
  esac
done
shift
cd "$HOME" && exec sh -c "$*"'
    }
    $stubs | items {|name, text|
        let file = $bin | path join $name
        $text | save --force $file
        ^chmod 755 $file
    } | ignore
}

def config-write [scratch: path, role: string] {
    let dir = $scratch | path join config offload
    mkdir $dir
    {
        role: $role, host: "192.0.2.1", port: 2222, knock: [1 2 3], router: null, router_tunnel: null
        forwards: {ollama: 11434}
    } | to nuon | save --force ($dir | path join config.nuon)
}

# offload in the repo with the scratch environment; stdout, stderr and the exit code.
def offload-run [scratch: path, repo: path, args: list<string>, input: string = ""]: nothing -> record {
    let env_scratch = {
        HOME: ($scratch | path join home)
        XDG_CONFIG_HOME: ($scratch | path join config)
        XDG_STATE_HOME: ($scratch | path join state)
        XDG_RUNTIME_DIR: ($scratch | path join run)
        OFFLOAD_ROOT: ($scratch | path join root)
        PATH: ([($scratch | path join bin)] ++ $env.PATH)
    }
    with-env $env_scratch {
        cd $repo
        $input | ^$nu.current-exe --no-config-file --stdin $SCRIPT ...$args | complete
    }
}

def repo-state [repo: path]: nothing -> record {
    {
        head: (^git -C $repo rev-parse HEAD | str trim)
        index: (^git -C $repo diff --cached --name-only | str trim)
        status: (^git -C $repo status --porcelain | str trim)
        refs: (^git -C $repo for-each-ref --format "%(refname)" refs/heads | str trim)
    }
}

# One role's whole run: the snapshot carries tracked and staged changes but not untracked files, the code comes back,
# ls shows it, fetch brings the worktree back as a ref and listed paths as files, and the repo is untouched.
def flow-check [scratch: path, repo: path, role: string] {
    config-write $scratch $role
    let before = repo-state $repo
    let started = offload-run $scratch $repo [--detach -- sh -c 'cat tracked.txt staged.txt; test ! -e untracked.txt && echo clean; echo made > result.txt; exit 3']
    if $started.exit_code != 0 { fail $"($role): start: ($started.stderr)" }
    let job = $started.stdout | str trim
    if not (job-id-valid $job) { fail $"($role): start printed ($job | to nuon)" }

    let attached = offload-run $scratch $repo [attach $job]
    if $attached.exit_code != 3 { fail $"($role): attach exit ($attached.exit_code): ($attached.stderr)" }
    if $attached.stdout != "changed\nstaged\nclean\n" { fail $"($role): attach output ($attached.stdout | to nuon)" }

    let listed = offload-run $scratch $repo [host ls]
    let row = $listed.stdout | from nuon | where job == $job
    if ($row | length) != 1 or $row.0.state != "exit 3" { fail $"($role): host ls ($listed.stdout)" }

    let fetched = offload-run $scratch $repo [fetch $job]
    if $fetched.exit_code != 0 { fail $"($role): fetch: ($fetched.stderr)" }
    let made = ^git -C $repo show $"(ref-result $job):result.txt" | str trim
    if $made != "made" { fail $"($role): result ref holds ($made | to nuon)" }

    let unpacked = offload-run $scratch $repo [fetch $job result.txt]
    if $unpacked.exit_code != 0 or (open --raw ($repo | path join result.txt) | str trim) != "made" {
        fail $"($role): fetch of a path: ($unpacked.stderr)"
    }
    rm ($repo | path join result.txt)
    let escape = offload-run $scratch $repo [fetch $job ../outside]
    if $escape.exit_code == 0 { fail $"($role): fetch took ../outside" }

    let after = repo-state $repo
    if $after != $before { fail $"($role): the repo changed: ($before | to nuon) -> ($after | to nuon)" }

    # one hostile word stays one literal argument on the target
    let hostile = "'; touch pwned; echo '"
    let word = offload-run $scratch $repo [--detach -- printf "%s|" $hostile '$(touch pwned2)']
    let shown = offload-run $scratch $repo [attach ($word.stdout | str trim)]
    if $shown.stdout != $"($hostile)|$\(touch pwned2\)|" { fail $"($role): hostile argument came out ($shown.stdout | to nuon)" }
    let worktrees = glob ($scratch | path join "**/pwned*")
    if ($worktrees | is-not-empty) { fail $"($role): the argument ran: ($worktrees)" }
}

# An agent's worktree past the job's commit, by its own commit and then kept dirty for the next session: fetch still
# brings each job's worktree back.
def agent-check [scratch: path, repo: path] {
    config-write $scratch target
    let client = "test-client"
    let bare = (offload-run $scratch $repo [host init $client repo]).stdout | from nuon | get bare
    let commit = ^git -C $repo rev-parse HEAD | str trim
    let jobs = [a1 a2] | each {|nonce| job-id repo (date now) $nonce }
    for job in $jobs { ^git -C $repo push --no-verify --quiet $bare $"($commit):(ref-source $job)" }
    let request = {job: $jobs.0, client: $client, slug: repo, kind: agent, commit: $commit, command: []}
    let refused = offload-run $scratch $repo [host start] ($request | to nuon)
    if $refused.exit_code == 0 or not ($refused.stderr =~ "cannot ask") { fail $"agent: an unknown device started: ($refused.stderr)" }
    let trust = $scratch | path join root var lib offload trust
    mkdir $trust
    {device: $client, since: (date now)} | to nuon | save ($trust | path join $"($client).nuon")
    let gate = $scratch | path join root run offload gate
    mkdir $gate
    {gamemode: true, obs: false} | to json | save ($gate | path join 1000.json)
    let busy = offload-run $scratch $repo [host start] ($request | to nuon)
    if $busy.exit_code == 0 or not ($busy.stderr =~ "gamemode") { fail $"agent: started while a game runs: ($busy.stderr)" }
    rm ($gate | path join 1000.json)
    let started = offload-run $scratch $repo [host start] ($request | to nuon)
    if $started.exit_code != 0 { fail $"agent: start: ($started.stderr)" }
    let worktree = $started.stdout | from nuon | get worktree
    "committed\n" | save ($worktree | path join agent.txt)
    ^git -C $worktree add agent.txt
    ^git -C $worktree -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit --quiet -m agent
    "dirty\n" | save ($worktree | path join dirty.txt)
    let again = offload-run $scratch $repo [host start] ($request | update job $jobs.1 | to nuon)
    if $again.exit_code != 0 or ($again.stdout | from nuon | get note) == null { fail $"agent: second start: ($again.stderr)" }
    for job in $jobs {
        let fetched = offload-run $scratch $repo [fetch $job]
        if $fetched.exit_code != 0 { fail $"agent: fetch ($job): ($fetched.stderr)" }
        let files = [agent.txt dirty.txt] | each {|f| ^git -C $repo show $"(ref-result $job):($f)" | str trim }
        if $files != [committed dirty] { fail $"agent: ($job)'s result ref holds ($files | to nuon)" }
    }
}

def main [] {
    pure-check
    if (which git sh tar | length) < 3 { print --stderr "offload.test: skipped the runs: needs git, sh and tar"; return }
    let scratch = mktemp --directory --tmpdir offload-test-XXXXXX
    stubs-write ($scratch | path join bin)
    let home_bin = $scratch | path join home .local bin
    mkdir $home_bin
    ^ln -s $SCRIPT ($home_bin | path join offload)
    mkdir ($scratch | path join run)

    let repo = $scratch | path join repo
    mkdir $repo
    ^git -C $repo init --quiet
    "original\n" | save ($repo | path join tracked.txt)
    ^git -C $repo add tracked.txt
    ^git -C $repo -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit --quiet -m init
    "changed\n" | save --force ($repo | path join tracked.txt)
    "new\n" | save ($repo | path join untracked.txt)
    "staged\n" | save ($repo | path join staged.txt)
    ^git -C $repo add staged.txt

    flow-check $scratch $repo target
    flow-check $scratch $repo client
    agent-check $scratch $repo
    rm --recursive --force $scratch
}
