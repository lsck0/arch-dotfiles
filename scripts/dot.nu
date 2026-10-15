#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname | path dirname
const LIB = $REPO | path join scripts lib
use ($LIB | path join log.nu) *
use ($LIB | path join state.nu) [SYSTEM_REPO SYSTEM_STATE state-dir]
use ($LIB | path join platform.nu) [platform-load platform-env]
use ($LIB | path join profile.nu) [profile-load profile-has]
use ($LIB | path join options.nu) [OPTION_ENABLE options-schema option-value-errors options-notify options-events-file options-to-nuon]
use ($LIB | path join modules.nu) [modules-graph modules-packages modules-eval]
use ($LIB | path join pipeline.nu) [pipeline-load pipeline-plan pipeline-apply]
use ($LIB | path join converge.nu) [state-read observe decls-check plan-module recorded-hashes apply-module state-write]
use ($LIB | path join secrets.nu) [secret-is-plaintext]
use ($LIB | path join written.nu) [written-begin written-prune written-end preserve-prune preserve-report tty-confirm]
use ($LIB | path join ledger.nu) [ledger-units ledger-get ledger-set packages-convergence]
use ($LIB | path join migrate.nu) [migrations-run migrations-pending migrations-list migration-run]
use ($LIB | path join sandbox.nu) [plan-sandbox plan-snapshot-units plan-report plan-end]
use ($LIB | path join fetch.nu) [fetch-file-run fetch-git-run]
use ($LIB | path join bootstrap.nu) [bootstrap-run]
use ($LIB | path join stage.nu) [stage-run]
use ($LIB | path join gate.nu) [gate-lint gate-tools gate-palette]
use ($LIB | path join vm.nu) [USER PLATFORM vm-run vm-logs vm-drill vm-destroy vm-type screenshot]
use ($LIB | path join yubikey.nu) [yubikey-init yubikey-seal yubikey-unlock yubikey-lock]
use ($LIB | path join audit.nu) [audit-run audit-rotated audit-drilled audit-remind]
use ($LIB | path join drift.nu) [drift-report drift-publish drift-view]
use ($LIB | path join doctor.nu) [doctor-run]
use ($LIB | path join system.nu) [system-pack system-archive ENTRY]
use ($LIB | path join wallpaper.nu) [wallpaper-get wallpaper-list wallpaper-set wallpaper-random wallpaper-pick]
use ($LIB | path join rollback.nu) [rollback-run rollback-resolve]
use ($LIB | path join sync.nu) [sync-run]

const FAILURES = "FAILURES.config"
const EXIT_SYSTEM_PENDING = 3
const CRASH_LOG_LINES = 20
const MIRROR_LIST = "mirror/packages.txt"
const FAILURES_INSTALL = "FAILURES.install"
# dot stage retries an abort, moves on from a run that only recorded failures
const EXIT_ABORTED = 2
# pinned so a generation installs what it was tested with
const NIXPKGS = "github:NixOS/nixpkgs/b6c8664de9b6cc07fe5666a29f91884ba81197c4"
const FLATHUB = "https://dl.flathub.org/repo/flathub.flatpakrepo"
# core/git's lfs filter, which a first apply pulls before it exists; without it lfs pull skips the checkout
const LFS_FILTER = [
    -c "filter.lfs.clean=git-lfs clean -- %f" -c "filter.lfs.smudge=git-lfs smudge -- %f"
    -c "filter.lfs.process=git-lfs filter-process" -c filter.lfs.required=true
]
# flatpak's profile.d puts its exports on the session's data dirs; without them each install prints a note
const FLATPAK_SYSTEM_EXPORTS = "/var/lib/flatpak/exports/share"
const FLATPAK_USER_EXPORTS = ".local/share/flatpak/exports/share"
const DATA_DIRS_DEFAULT = "/usr/local/share:/usr/share"
# seeds a root copy that predates the nu entry: a fixed script, no repo code as root
const SYSTEM_SEED = 'set -e; umask 022; copy=$1; mkdir -p "${copy%/*}"; exec 9>"${copy%/*}/lock"; flock 9; rm -rf "$copy.new"; mkdir "$copy.new"; tar -x --no-same-owner --no-same-permissions -C "$copy.new" -f -; printf "%s\n" "$2" > "$copy.new/.source"; rm -rf "$copy"; mv "$copy.new" "$copy"'
const THEME_STAMP_PATHS = [configs/core/wallust configs/core/themes 'configs/*/*/mod.nu' scripts/lib/wallpaper.nu]
const THEME_DEFAULT_WALLPAPER = "alena-aenami-cover-art-007-3.jpg"
# discord recolours from spotify's palette; discord and gtk would race a second switch
const THEME_FOREGROUND = [socials/spotify socials/discord desktop/gtk]

def concat []: list -> list {
    reduce --fold [] {|part, acc| $acc ++ $part }
}

def jobs []: nothing -> int {
    let jobs = $env.DOTFILES_JOBS? | default (sys cpu | length) | into int
    if $jobs < 1 { error make {msg: $"DOTFILES_JOBS=($jobs) is not a positive number"} }
    $jobs
}

def build []: nothing -> record {
    let head = try { ^git -C $REPO rev-parse --short=12 HEAD | str trim } catch { "none" }
    let dirty = (try { ^git -C $REPO status --porcelain --ignore-submodules=all | str trim } catch { "" }) | is-not-empty
    {commit: $head, dirty: $dirty, nu: (version | get version)}
}

def guarded [name: string, body: closure]: nothing -> any {
    run-begin $name | ignore
    $env.DOTFILES = $REPO
    $env.LOG_TAG = "dot"
    try {
        span $name {} $body
    } catch {|err|
        # own refusals (error make) name the fix themselves, no crash record
        if ($err.debug | str starts-with "LabeledError") {
            log-err $err.msg
            run-journal
            exit 1
        }
        let run = $env.DOT_RUN_FILE
        let file = $run | path dirname | path dirname | path join crash.json
        let tail = if ($run | path exists) { open --raw $run | lines | last $CRASH_LOG_LINES } else { [] }
        {run: $env.DOT_RUN_ID, command: $name, error: $err.msg, debug: $err.debug, build: (build), log: $tail} | save --force $file
        print -e $err.rendered
        log-record PANIC $"crash record: ($file)" {msg_detail: $err.msg}
        run-journal
        exit 1
    }
}

def summary [results: table]: nothing -> nothing {
    let outcomes = $results | get outcomes | concat
    let counts = $outcomes | group-by kind | items {|k, v| $"($v | length) ($k)" } | str join ", "
    let busy = $results | where {|r| ($r.outcomes | is-not-empty) or ($r.log | str trim | is-not-empty) } | get id | uniq
    let skipped = ($results.id | uniq | length) - ($busy | length)
    log-info $"($results.id | uniq | length) modules, ($skipped) unchanged(if ($counts | is-empty) { '' } else { $', ($counts)' })" {kind: summary}
    let slow = $results | sort-by ms --reverse | first 5 | each { $"($in.ms / 1000 | math round --precision 1)s ($in.id)" } | str join ", "
    log-debug $"slowest: ($slow)"
}

def plan-print [planned: table, verb: string]: nothing -> nothing {
    for m in $planned {
        let shown = $m.actions | where kind != skip
        if $m.error != null {
            print $"($m.id): error: ($m.error)"
        } else if ($shown | is-not-empty) {
            print $m.id
            $shown | each {|a| print $"  ($a.kind | fill --width 8) ($a.target)(if ($a.reason | is-empty) { '' } else { $'  (($a.reason))' })" } | ignore
        }
    }
}

def --env link-run [mods: list<string>, force: bool, plan: bool]: nothing -> table {
    let ctx = pipeline-load $REPO user
    # zshrc sets it only interactively; mason's go would create ~/go
    $env.GOPATH = $nu.home-dir | path join .go
    let planned = pipeline-plan $ctx link $mods $force
    if $plan {
        plan-print $planned link
        return []
    }
    let full = $mods | is-empty
    $env.DOT_FULL_RUN = $full
    failures-open
    if $full { written-begin }
    let results = with-env (platform-env $ctx.platform) { pipeline-apply $ctx $planned link (jobs) }
    # theme outputs are desired state too: one removed by an unlink returns with the link
    let wallpaper = $nu.home-dir | path join .cache wal wallpaper
    let themed = if ($wallpaper | path exists) {
        let ids = $planned | where native | get id
        pipeline-plan $ctx theme $ids false [(^readlink -f $wallpaper | str trim)] | where native | pipeline-apply $ctx $in theme (jobs) [(^readlink -f $wallpaper | str trim)]
    } else { [] }
    if $full {
        if ($results | all { $in.ok }) { written-prune (owned-targets) } else { written-end }
        for dir in [$nu.home-dir ($nu.home-dir | path join .local bin)] {
            ls -a $dir | where type == symlink | where {|l| not ($l.name | path exists) and ((^readlink $l.name) | str starts-with $"($REPO)/") } | each { rm $in.name } | ignore
        }
        let units = ledger-units $REPO $ctx.platform.groups user
        $units.by_hand | each { log-info $"enabled by hand, not managed: ($in)" } | ignore
        theme-init
    }
    summary ($results ++ $themed)
    $results ++ $themed
}

def owned-targets []: nothing -> list<string> {
    glob (state-dir | path join modules **/*.nuon) | each { open $in | get outputs.target } | concat
}

def theme-init []: nothing -> nothing {
    # over the worktree, not ls-files -s: an index stamp never changes on an uncommitted theming edit
    let files = ^git -C $REPO ls-files ...$THEME_STAMP_PATHS | lines | where $it != "" | each {|f| $REPO | path join $f }
    let stamp = ^sha1sum ...$files | ^sha1sum | str trim
    let cache = $nu.home-dir | path join .cache wal
    let current = try { open --raw ($cache | path join .theme-stamp) | str trim } catch { "" }
    if ($cache | path join wallpaper | path exists) and $current == $stamp {
        return
    }
    # readlink -f prints a missing path too, so a fresh home has to be told apart first
    let link = $cache | path join wallpaper
    let wallpaper = if ($link | path exists) { ^readlink -f $link | str trim } else { $THEME_DEFAULT_WALLPAPER }
    wallpaper-set $wallpaper --sync
    $"($stamp)\n" | save --force ($cache | path join .theme-stamp)
}

# per-run failures published by one rename, so concurrent runs never clobber each other's
def --env failures-open []: nothing -> nothing {
    if ($env.FAILURES_FILE? | is-empty) {
        $env.FAILURES_FILE = $env.DOT_RUN_FILE | str replace ".jsonl" ".failures"
        $env.DOT_FAILURES_OWNED = true
    }
}

def finish [results: table]: nothing -> nothing {
    run-journal
    let owned = $env.DOT_FAILURES_OWNED? == true
    let failures = if $owned and ($env.FAILURES_FILE | path exists) { open --raw $env.FAILURES_FILE | str trim } else { "" }
    if ($failures | is-not-empty) {
        let published = $REPO | path join $FAILURES
        $"($failures)\n" | save --force $"($published).($env.DOT_RUN_ID)"
        mv --force $"($published).($env.DOT_RUN_ID)" $published
        print "=== FAILED ==="
        print $failures
        exit 1
    }
    if ($results | any { not $in.ok }) { exit 1 }
    # only a full run clears the last list; a partial run leaves it
    if $owned and ($env.DOT_FULL_RUN? == true) { rm --force ($REPO | path join $FAILURES) }
}

const USAGE = "dot: this machine as code. `dot update` brings it to the current generation

  update                       pull, snapshot, migrate, install, apply
  status | doctor              at a glance | full health check
  sync                         back up, commit the signed generation, push
  theme [set|random|get|list]  wallpaper and theme

  plan [mod...]                what an apply would do, touching nothing
  apply [--force]              system layer, then user layer; --force overwrites drift
  link [mod...] | system       user layer | system layer alone
  install                      every declared package
  unlink | remove <mod>        undo a module | also turn it off

  list | graph                 modules | run order
  options [mod]                options and values; set | unset <mod>.<key>
  diff | adopt | explain       drift | keep a live edit | who wrote a path
  log [run] [--trace]          a run's records or span tree

  secrets [unlock|lock|init]   the yubikey-backed secrets
  backup | restore <mod>       app state into the repo | back out
  rollback [gen]               an earlier generation
  test lint|check|run|shot     static gates | the vm test

  more: audit bootstrap drift fetch gen migrate packages prune stage watch
  dot <command> --help for its flags"

# infrastructure as code for this machine; `dot update` brings it to the current generation
def main []: nothing -> nothing {
    print $USAGE
}

# every module: group, kind, verbs, whether this machine runs it
def "main list" [--json]: nothing -> any {
    guarded list {
        let ctx = pipeline-load $REPO user
        let rows = $ctx.modules | each {|m|
            {id: $m.id, kind: (if ($m.native | is-empty) { "legacy" } else { "native" }), verbs: ($m.verbs | str join " "), enabled: $m.cfg.enable, packages: ($m.meta.packages.pacman | length)}
        }
        if $json { $rows | to json } else { $rows }
    }
}

# the run order: each enabled module with its level and what it waits for
def "main graph" [--system]: nothing -> any {
    guarded graph {
        let ctx = pipeline-load $REPO (if $system { "system" } else { "user" })
        let verb = if $system { "system" } else { "link" }
        modules-graph $REPO ($ctx.modules | where {|m| $verb in $m.verbs and $m.cfg.enable }) | select level id after
        | update after { str join " " }
    }
}

# what an apply would do, touching nothing; --sandbox adds the legacy modules' write set
def "main plan" [...mods: string, --system, --sandbox, --force]: nothing -> nothing {
    guarded plan {
        if $system {
            let ctx = pipeline-load $REPO system
            plan-print (pipeline-plan $ctx system $mods $force) system
        } else {
            link-run $mods $force true | ignore
        }
        let pending = migrations-pending $REPO (if $system { "system" } else { "user" })
        if ($pending | is-not-empty) { print $"migrations pending: ($pending.id | str join ' ')" }
        let waiting = try { open --raw (pending-file) | lines | uniq } catch { [] }
        if ($waiting | is-not-empty) { print $"system part pending for: ($waiting | str join ' '); dot apply runs it" }
        let ctx = pipeline-load $REPO system
        let declared = modules-packages $REPO $ctx.modules $ctx.platform
        let extra = packages-convergence $declared.pacman $ctx.platform.packages_keep
        if ($extra.remove | is-not-empty) {
            print $"installed, declared by no module \(($extra.remove | length)\): ($extra.remove | str join ' ')\n  dot install removes them after a yes"
        }
        if $sandbox {
            let dir = mktemp --directory
            plan-snapshot-units $dir user
            let roots = [$nu.home-dir] | append (if ($REPO | str starts-with $nu.home-dir) { [] } else { [$REPO] })
            let status = with-env {FAILURES_FILE: ($dir | path join FAILURES)} {
                plan-sandbox $dir $roots [($REPO | path join scripts dot.nu) link ...$mods]
            }
            print (plan-report $dir ($dir | path join FAILURES))
            plan-end $dir
            if $status != 0 { log-err $"the sandboxed run itself failed \(($status)\), the write set above is partial" }
        }
    }
}

# converge the user layer: every enabled module's link verb, unchanged native modules skipped
def "main link" [...mods: string, --force]: nothing -> nothing {
    guarded link { link-run $mods $force false | finish $in }
}

def mirror-list []: nothing -> string {
    let ctx = pipeline-load $REPO system
    let all = $ctx.modules | update selected true | update cfg { upsert enable true }
    let extras = glob ($REPO | path join platforms *.nuon) | where not ($it | str ends-with ".options.nuon") | each { open $in | get --optional extra_packages | default [] } | flatten
    # a computed list depends on detection: every choice of every option
    let variants = $all | where {|m| "packages" in $m.native } | each {|m|
        $m.options | items {|name, spec| $spec.choices? | default [] | each {|c| {m: $m, cfg: ($m.cfg | upsert $name $c)} } } | flatten
    } | flatten
    let candidates = $variants | each {|v| modules-eval [$v.m] packages {$v.m.id: $v.cfg} [] | get 0.decls | get --optional 0 | default {} | select --optional pacman native | values | flatten } | flatten
    let platform = $ctx.platform | update form_factor desktop | update extra_packages ($extras ++ $candidates)
    modules-packages $REPO $all $platform | get pacman | str join "\n" | $"($in)\n"
}

def admin []: nothing -> bool {
    ^id -nG | split row " " | any { $in == wheel }
}

# DOT_SYSTEM=skip: tests and agents must never put a root prompt on the screen
def system-allowed []: nothing -> bool {
    $env.DOT_SYSTEM? != "skip" and (admin)
}

# pacman draws its bars only on a terminal, so rerun under script to keep and log them
def --env pty-log [name: string, args: list<string>]: nothing -> nothing {
    if ($env.DOT_PTY_LOG? | is-not-empty) { return }
    # before the re-exec: its pty stdin would look like a person even under dot stage's </dev/null
    if not (is-terminal --stdin) { $env.DOTFILES_UNATTENDED = "1" }
    if (is-terminal --stdout) and (which script | is-not-empty) {
        let cmd = [nu --no-config-file ($REPO | path join scripts dot.nu) ...$args] | each {|w| $"'($w | str replace --all "'" "'\\''")'" } | str join " "
        exec env DOT_PTY_LOG=1 script -qe -c $cmd ($REPO | path join $"($name).log")
    }
}

def system-run [stage: string, --snapshot, --force]: nothing -> int {
    let runner = $env.DOTFILES_ROOT_RUNNER? | default sudo
    let head = ^git -C $REPO rev-parse HEAD | str trim
    let entry = $SYSTEM_REPO | path join $ENTRY
    let rollback = $env.DOT_ROLLBACK? == "1"
    if not ($entry | path exists) {
        if $runner != "sudo" { error make {msg: $"($SYSTEM_REPO) has no ($ENTRY) yet, run dot apply at a terminal once"} }
        system-pack $REPO --rollback=$rollback | ^sudo sh -c $SYSTEM_SEED sh $SYSTEM_REPO $head
    }
    let pin = $env.LSCK0_SNAPSHOT? | default "" | if ($in | is-empty) { [] } else { [--pin $in] }
    let forced = if $force { [--force] } else { [] }
    let flags = [--snapshot=($snapshot) --unattended=($env.DOTFILES_UNATTENDED? == "1")] ++ $pin ++ $forced
    let archive = system-archive $REPO (platform-load $REPO).facts.wireguard? --rollback=$rollback
    try { $archive | ^$runner $entry apply $head $stage ...$flags; 0 } catch {|e| $e.exit_code? | default 1 }
}

def system-failed [stage: string]: nothing -> nothing {
    fail $"system layer: ($stage)"
    let root = $SYSTEM_STATE | path join FAILURES
    if ($root | path exists) { open --raw $root | save --append $env.FAILURES_FILE }
}

# secrets and lfs first: the root copy and the links take the working tree as it is
def --env apply-run [system: bool, user: bool, force: bool]: nothing -> table {
    failures-open
    if (profile-has secrets) { try { yubikey-unlock } catch {|e| fail $"dot secrets unlock: ($e.msg)" } }
    if (which git-lfs | is-not-empty) { try { ^git -C $REPO ...$LFS_FILTER lfs pull } catch { fail "git lfs pull" } }
    if $system {
        if (system-run config --snapshot --force=$force) == 0 { rm --force (pending-file) } else { system-failed config }
    }
    if $user { link-run [] $force false } else { [] }
}

# converge the machine: the system layer from the root-owned copy, then the user layer
def "main apply" [--user, --no-system, --force]: nothing -> nothing {
    let flags = [[--user $user] [--no-system $no_system] [--force $force]] | where { $in.1 } | each { $in.0 }
    pty-log config ([apply] ++ $flags)
    guarded apply { apply-run (not $user and not $no_system and (system-allowed)) true $force | finish $in }
}

# the system layer alone: a snapshot, then every system verb from the root-owned copy
def "main system" [--force]: nothing -> nothing {
    pty-log config ([system] ++ (if $force { [--force] } else { [] }))
    guarded system {
        if not (system-allowed) {
            print "note: system part pending, DOT_SYSTEM=skip"
            exit $EXIT_SYSTEM_PENDING
        }
        apply-run true false $force | finish $in
    }
}

# reverse a native module's last apply; files changed since stay, originals come back
def "main unlink" [mod: string]: nothing -> nothing {
    guarded unlink { unlink-run $mod | finish $in }
}

def --env unlink-run [mod: string]: nothing -> table {
    let ctx = pipeline-load $REPO user
    let m = $ctx.modules | where id == $mod | get --optional 0
    if $m == null or ($m.native | is-empty) {
        error make {msg: $"($mod) is no native module; unlink needs its mod.nu"}
    }
    failures-open
    let extra = if "unlink" in $m.native { modules-eval [$m] unlink {$mod: $m.cfg} [] | get 0.decls } else { [] }
    decls-check $mod $extra
    let rows = [link theme] | each {|verb|
        let prev = (state-read $mod $verb).outputs
        let seen = observe ($prev | where kind != unit | get target) ($prev | where kind == unit | get target) user
        let actions = plan-module $mod (if $verb == "link" { $extra } else { [] }) $prev $seen (recorded-hashes) $REPO false
        {verb: $verb, prev: $prev, actions: $actions}
    }
    plan-print ($rows | each {|r| {id: $"($mod) ($r.verb)", native: true, error: null, actions: $r.actions} }) unlink
    let outcomes = $rows | each {|r|
        let done = apply-module $r.actions $m.dir user
        state-write $mod $r.verb "" $r.actions $done $r.prev
        $done
    } | concat
    let kept = $rows | get actions | concat | where kind == drift
    if ($kept | is-not-empty) { log-warn $"left in place, changed since the last apply: ($kept.target | str join ' ')" }
    [{id: $mod, ok: ($outcomes | all { $in.ok }), outcomes: $outcomes, ms: 0, log: "", error: null}]
}

# unlink a module, turn it off (--machine: for the machine), offer its packages for removal
def "main remove" [mod: string, --machine, --yes]: nothing -> nothing {
    guarded remove {
        let ctx = pipeline-load $REPO user
        let dependents = $ctx.modules | where {|m| $m.cfg.enable and $mod in $m.meta.deps } | get id
        if ($dependents | is-not-empty) { error make {msg: $"($dependents | str join ', ') depend on ($mod), remove those first"} }
        unlink-run $mod | ignore
        option-write $mod enable false $machine | ignore
        let mine = $ctx.modules | where id == $mod | get 0.meta.packages.pacman
        let others = modules-packages $REPO ($ctx.modules | where id != $mod) $ctx.platform | get pacman
        let only = $mine | where $it not-in $others
        if ($only | is-not-empty) {
            print $"packages only ($mod) declares: ($only | str join ' ')"
            if $yes or (tty-confirm "remove them?") { ^sudo pacman -Rns ...$only }
        }
    }
}

# flatpak in user scope: a system deploy needs a polkit agent the unattended chain lacks
def install-user [declared: record]: nothing -> nothing {
    # stable only, a project pins nightly in its rust-toolchain.toml
    if (which rustup | is-not-empty) { try { ^rustup default stable } catch { fail "rustup default stable" } }
    let apps = $declared.flatpak | transpose app commit
    if ($apps | is-not-empty) and (which flatpak | is-not-empty) {
        let exports = [($nu.home-dir | path join $FLATPAK_USER_EXPORTS) $FLATPAK_SYSTEM_EXPORTS]
        let dirs = $exports ++ ($env.XDG_DATA_DIRS? | default $DATA_DIRS_DEFAULT | split row ":") | uniq | str join ":"
        with-env {XDG_DATA_DIRS: $dirs} {
            if (^flatpak remote-add --user --if-not-exists flathub $FLATHUB | complete).exit_code != 0 {
                fail "flatpak remote-add --user flathub"
            } else {
                let deployed = {|app| ^flatpak info --user --show-commit $app | complete | if $in.exit_code == 0 { $in.stdout | str trim } else { "" } }
                for a in $apps {
                    if not ($a.commit =~ '^[0-9a-f]{64}$') { fail $"flatpak ($a.app): no pinned commit"; continue }
                    let now = do $deployed $a.app
                    if $now != $a.commit {
                        # a mask also holds back an explicit update
                        if $a.app in (^flatpak mask --user | lines | str trim) { ^flatpak mask --user --remove $a.app }
                        if $now == "" and (try { ^flatpak install --user --noninteractive flathub $a.app; false } catch { true }) { fail $"flatpak install --user ($a.app)"; continue }
                        try { ^flatpak update --user --noninteractive $"--commit=($a.commit)" $a.app } catch { fail $"flatpak update --user --commit=($a.commit) ($a.app)" }
                    }
                    try { ^flatpak mask --user $a.app } catch { fail $"flatpak mask --user ($a.app)" }
                }
                ledger-set flatpak ($apps | each {|a| let c = do $deployed $a.app; if $c == "" { "" } else { $"($a.app) ($c)" } })
            }
        }
    }
    if ($declared.nix | is-not-empty) and (which nix | is-not-empty) {
        let nix = [--extra-experimental-features "nix-command flakes"]
        # nix profile add stacks a duplicate on every rerun
        let missing = $declared.nix | where $it not-in (^nix ...$nix profile list --json | from json | get elements | columns)
        if ($missing | is-not-empty) {
            try { ^nix ...$nix profile add ...($missing | each { $"($NIXPKGS)#($in)" }) } catch { fail $"nix profile add ($missing | str join ' ')" }
        }
    }
}

def --env install-run [user: bool, yes: bool, snapshot: bool]: nothing -> int {
    let system = not $user and (system-allowed)
    $env.FAILURES_FILE = $env.DOT_RUN_FILE | str replace ".jsonl" ".install-failures"
    "" | save --force $env.FAILURES_FILE
    if $system {
        let status = system-run install --snapshot=$snapshot
        if $status == $EXIT_ABORTED {
            fail "system layer: install aborted"
            # the chain may give up after this, so the reason has to outlive the run file
            $"(open --raw $env.FAILURES_FILE | str trim)\n" | save --force ($REPO | path join $FAILURES_INSTALL)
            hide-env FAILURES_FILE
            return $EXIT_ABORTED
        }
        if $status != 0 { system-failed install }
    }
    let ctx = pipeline-load $REPO user
    install-user (modules-packages $REPO $ctx.modules $ctx.platform)
    if $system { ^sudo ($SYSTEM_REPO | path join $ENTRY) packages --unattended=($env.DOTFILES_UNATTENDED? == "1") ...(if $yes { [--yes] } else { [] }) }
    let failed = open --raw $env.FAILURES_FILE | str trim
    hide-env FAILURES_FILE
    if ($failed | is-empty) { rm --force ($REPO | path join $FAILURES_INSTALL); return 0 }
    $"($failed)\n" | save --force ($REPO | path join $FAILURES_INSTALL)
    print $"=== FAILED ===\n($failed)"
    1
}

# install every declared package after a snapshot, then remove undeclared ones after a yes
def "main install" [--yes, --user]: nothing -> nothing {
    pty-log install ([install] ++ (if $yes { [--yes] } else { [] }) ++ (if $user { [--user] } else { [] }))
    guarded install { exit (install-run $user $yes true) }
}

# declared packages of a kind, one per line; --groups/--form-factor for another machine
def "main packages" [kind: string = "pacman", --groups: string, --form-factor: string]: nothing -> nothing {
    guarded packages {
        let ctx = pipeline-load $REPO system
        let chosen = $groups | default "" | split row --regex '[ ,]+' | where $it != ""
        let mods = if ($chosen | is-empty) { $ctx.modules } else { $ctx.modules | update selected {|m| $m.group in $chosen or $m.group == "" } }
        let platform = if ($chosen | is-empty) { $ctx.platform } else { $ctx.platform | update extra_packages [] | update form_factor ($form_factor | default $ctx.platform.form_factor) }
        let out = modules-packages $REPO $mods $platform | get $kind
        print (if $kind == "flatpak" { $out | items {|app, commit| $"($app) ($commit)" } } else { $out } | str join "\n")
    }
}

# regenerate mirror/packages.txt; --check fails when it is stale
def "main gen" [--check]: nothing -> nothing {
    guarded gen {
        if $check {
            if (open --raw ($REPO | path join $MIRROR_LIST)) != (mirror-list) { error make {msg: $"($MIRROR_LIST) is stale, run dot gen"} }
            return
        }
        mirror-list | save --force ($REPO | path join $MIRROR_LIST)
    }
}

def toggle-script [name: string]: nothing -> path {
    $REPO | path join scripts toggles $"toggle-($name).nu"
}

def option-runtime [spec: record]: nothing -> any {
    if ($spec.toggle? | default null) == null { return null }
    try { ^(toggle-script $spec.toggle) get | str trim } catch { null }
}

# every option with its value and source; --json adds schema and live state for a frontend
def "main options" [mod?: string, --json]: nothing -> any {
    guarded options {
        let ctx = pipeline-load $REPO user
        let mods = $ctx.modules | where {|m| $mod == null or $m.id == $mod }
        if $json {
            let modules = $mods | each {|m|
                let options = options-schema $m | items {|key, spec|
                    $spec | reject --optional env toggle | merge {
                        key: $key
                        value: ($m.cfg | get $key)
                        source: ($m.sources | get $key)
                        runtime: (if $spec.apply == "live" { option-runtime $spec } else { null })
                    }
                }
                {name: $m.id, label: $m.id, doc: ($m.meta.doc? | default ""), options: $options}
            }
            return ({modules: $modules} | to json --raw)
        }
        $mods | each {|m| options-schema $m | items {|key, spec| {module: $m.id, option: $key, value: ($m.cfg | get $key), source: ($m.sources | get $key)} } }
        | concat | where {|r| $mod != null or $r.option != "enable" or not $r.value }
    }
}

def option-target [target: string]: nothing -> record {
    let parts = $target | parse --regex '^(?<mod>.+)\.(?<key>[a-z][a-z0-9_]*)$' | get --optional 0
    if $parts == null { error make {msg: $"($target): want <group/module>.<option>"} }
    $parts
}

# a null value removes the key, so the layer below applies
def option-write [mod: string, key: string, value: any, machine: bool]: nothing -> record {
    let ctx = pipeline-load $REPO user
    let m = $ctx.modules | where id == $mod | get --optional 0
    if $m == null { error make {msg: $"no module ($mod); dot list shows them"} }
    let spec = options-schema $m | get --optional $key
    if $spec == null { error make {msg: $"($mod) has no option ($key); dot options ($mod) lists them"} }
    let bad = if $value == null { [] } else { option-value-errors $mod $key $spec $value "dot set" }
    if ($bad | is-not-empty) { error make {msg: ($bad | str join "\n")} }
    if $spec.scope == "machine" and not $machine { error make {msg: $"($mod).($key) is a machine option: dot set --machine"} }
    let file = if $machine { $ctx.platform.options_file } else { $ctx.profile.options_file }
    if $file == null or ($file | str starts-with "/etc/") { error make {msg: $"this machine's options are root's ($file | default '/etc/dotfiles'), not settable from here"} }
    let current = if ($file | path exists) { open $file } else { {} }
    let cell = [$mod $key] | into cell-path
    let updated = if $value == null { $current | reject --optional $cell } else { $current | upsert $cell $value }
    $updated | items {|id, opts| {id: $id, opts: $opts} } | where ($it.opts | is-not-empty) | reduce --fold {} {|e, acc| $acc | insert $e.id $e.opts }
    | options-to-nuon | $"($in)\n" | save --force $file
    let resolved = pipeline-load $REPO user | get modules | where id == $mod | first
    {module: $m, spec: $spec, value: ($resolved.cfg | get $key), source: ($resolved.sources | get $key)}
}

def option-apply [target: string, set: record]: nothing -> nothing {
    let runtime = match $set.spec.apply {
        "live" => {
            if "apply" in $set.module.native {
                let ctx = pipeline-load $REPO user
                pipeline-apply $ctx (pipeline-plan $ctx apply [$set.module.id] true) apply 1 | ignore
                null
            } else if ($set.spec.toggle? | default null) != null {
                let argv = match ($set.value | describe) { "bool" => [(if $set.value { "on" } else { "off" })], _ => [set ($set.value | into string)] }
                ^(toggle-script $set.spec.toggle) ...$argv
                option-runtime $set.spec
            } else { null }
        }
        $apply => {
            # a disabled module is skipped by link, so turning it off has to undo it here
            if ($target | str ends-with $".($OPTION_ENABLE)") and $set.value == false and ($set.module.native | is-not-empty) {
                unlink-run $set.module.id | ignore
                print $"note: ($set.module.id) unlinked; dot remove ($set.module.id) also drops its packages"
            } else if "link" in $set.module.verbs { link-run [$set.module.id] false false | ignore }
            # machine options reach the system verb only through the root-owned copy
            if $set.spec.scope == "machine" and "system" in $set.module.verbs and (admin) { system-part $target }
            if $apply != "relink" {
                log-note $"($target) takes effect after a ($apply)"
            }
            null
        }
    }
    options-notify $target $set.value $set.source $runtime
    if ($env.DOT_SYSTEM_PENDING? == true) { exit $EXIT_SYSTEM_PENDING }
}

def pending-file []: nothing -> path {
    state-dir | path join system-pending
}

def --env system-part [target: string]: nothing -> nothing {
    let tty = (^test -t 0 | complete).exit_code == 0
    let graphical = ($env.WAYLAND_DISPLAY? | is-not-empty) or ($env.DISPLAY? | is-not-empty)
    let runner = if $env.DOT_SYSTEM? == "skip" { null } else if $tty { "sudo" } else if $graphical and (which pkexec | is-not-empty) { "pkexec" } else { null }
    let ok = $runner != null and (with-env {DOTFILES_ROOT_RUNNER: $runner} { system-run config }) == 0
    if $ok { return }
    $"($target)\n" | save --append (pending-file)
    log-note $"($target): system part pending, runs on the next dot apply"
    $env.DOT_SYSTEM_PENDING = true
}

# set <module>.<option> to a value (nuon or json), validated, stored, applied as the option says
def "main set" [target: string, value: any, --machine, --no-system]: nothing -> nothing {
    if $no_system { $env.DOT_SYSTEM = "skip" }
    guarded set {
        let t = option-target $target
        # nu passes true, 3 or [a b] typed; a string may still be nuon or json (the settings window)
        let parsed = if ($value | describe) != "string" { $value } else { try { $value | from nuon } catch { try { $value | from json } catch { $value } } }
        option-apply $target (option-write $t.mod $t.key $parsed $machine)
    }
}

# reset one option (--machine: the platform's), its default comes back
def "main unset" [target: string, --machine, --no-system]: nothing -> nothing {
    if $no_system { $env.DOT_SYSTEM = "skip" }
    guarded unset {
        let t = option-target $target
        option-apply $target (option-write $t.mod $t.key null $machine)
    }
}

# every option and live state change as json lines {key, value, source, runtime}
def "main watch" []: nothing -> nothing {
    let file = options-events-file
    mkdir ($file | path dirname)
    if not ($file | path exists) { "" | save $file }
    ^tail --follow=name --retry --lines=0 $file
}

# drift: managed files changed since their last apply, links pointing elsewhere, units disabled
def "main diff" [mod?: string]: nothing -> any {
    guarded diff {
        let files = glob (state-dir | path join modules **/*.nuon)
        $files | each {|f|
            let id = $f | path dirname | path relative-to (state-dir | path join modules)
            if $mod != null and $id != $mod { return [] }
            let outs = open $f | get outputs
            let seen = observe ($outs | where kind != unit | get target) ($outs | where kind == unit | get target) user
            $outs | each {|o|
                let obs = $seen.paths | get --optional $o.target
                let state = match $o.kind {
                    "file" => (if $obs.type == "" { "missing" } else if $obs.hash != $o.hash { "changed" } else { null })
                    "link" => (if $obs.link? != $o.source { "relinked" } else { null })
                    "unit" => (if ($seen.units | get --optional $o.target) != "enabled" { "disabled" } else { null })
                }
                if $state == null { null } else { {module: $id, target: $o.target, drift: $state} }
            } | compact
        } | flatten
    }
}

# carry a live edit of a managed copy back into the module's source, so the next apply keeps it
def "main adopt" [file: path]: nothing -> nothing {
    guarded adopt {
        let target = $file | path expand
        let ctx = pipeline-load $REPO user
        let planned = pipeline-plan $ctx link [] true
        let found = $planned | get actions | concat | where target == $target and decl.kind == file | get --optional 0
        if $found == null { error make {msg: $"($target) is no file a module copies; dot diff lists the managed ones"} }
        if $found.decl.source == null { error make {msg: $"($target) is rendered by ($found.module), adopt it by editing its template"} }
        ^cp $target $found.decl.source
        log-info $"($target) -> ($found.decl.source | path relative-to $REPO)"
    }
}

# pick a wallpaper and theme with fzf
def "main theme" []: nothing -> nothing { guarded theme { wallpaper-pick } }
# the current wallpaper
def "main theme get" []: nothing -> nothing { guarded theme { print (wallpaper-get) } }
# the wallpapers for the largest monitor
def "main theme list" []: nothing -> nothing { guarded theme { print (wallpaper-list | str join "\n") } }
# a random wallpaper and its theme; --sync waits for every theme verb
def "main theme random" [--sync]: nothing -> nothing { guarded theme { wallpaper-random --sync=$sync } }
# switch to <name|path> and its theme; --sync waits for every theme verb
def "main theme set" [wallpaper: string, --sync]: nothing -> nothing { guarded theme { wallpaper-set $wallpaper --sync=$sync } }

# every module's theme verb for this wallpaper (--only foreground|background)
def "main theme apply" [wallpaper: path, ...mods: string, --only: string]: nothing -> nothing {
    guarded theme {
        let ctx = pipeline-load $REPO user
        let planned = pipeline-plan $ctx theme $mods true [$wallpaper]
        let results = if $only != "foreground" {
            pipeline-apply $ctx ($planned | where id not-in $THEME_FOREGROUND) theme (jobs) [$wallpaper]
        } else { [] }
        let ordered = if $only != "background" {
            let foreground = $THEME_FOREGROUND | each {|id| $planned | where id == $id } | concat | update after []
            pipeline-apply $ctx $foreground theme 1 [$wallpaper]
        } else { [] }
        $results ++ $ordered | where not ok | each { log-err $"theme: ($in.id) failed" } | ignore
    }
}

# pending one-time migrations (--system: root's); --baseline marks them run on a fresh install
def "main migrate" [--baseline, --system]: nothing -> nothing {
    guarded migrate {
        let done = migrations-run $REPO (if $system { "system" } else { "user" }) --baseline=$baseline
        if ($done | is-not-empty) { log-info $"migrations (if $baseline { 'marked' } else { 'applied' }): ($done | str join ' ')" }
    }
}

# the one command: pull the current generation, snapshot, migrate, install, apply
def "main update" [--yes]: nothing -> nothing {
    guarded update {
        if (^git -C $REPO status --porcelain --untracked-files=no --ignore-submodules=all | str trim | is-not-empty) { error make {msg: "the checkout has uncommitted changes; commit them with dot sync or stash them"} }
        if (try { ^git -C $REPO symbolic-ref -q --short HEAD | str trim } catch { "" }) != "master" { error make {msg: "HEAD is not on master, go back with: git switch master"} }
        ^git -C $REPO pull --ff-only
        migrations-run $REPO user | ignore
        if (install-run false $yes true) == $EXIT_ABORTED { exit $EXIT_ABORTED }
        if (system-allowed) { ^sudo ($SYSTEM_REPO | path join $ENTRY) migrate }
        apply-run (system-allowed) true false | finish $in
    }
}

# back to an earlier generation, undoing newer migrations; --snapshot lists pre-apply snapshots
def "main rollback" [target?: string, --snapshot, --full, --dry-run]: nothing -> nothing {
    guarded rollback {
        if $snapshot {
            ^sudo timeshift --list
            print "restore one with: sudo timeshift --restore --snapshot '<name>' (then reboot; kernel-resync fixes the esp)"
            return
        }
        if $target == null { error make {msg: "dot rollback <generation|commit> or --snapshot"} }
        let sha = rollback-resolve $target
        let later = migrations-list $REPO | where id in (ledger-get migration) | where {|m| (^git -C $REPO cat-file -e $"($sha):($m.file | path relative-to $REPO)" | complete).exit_code != 0 }
        let stuck = $later | where not reversible
        if ($stuck | is-not-empty) { error make {msg: $"($target) predates migration ($stuck.id | str join ', '), which has no down"} }
        if not $dry_run { $later | reverse | each { migration-run $in down } | ignore }
        rollback-run $target --full=$full --dry-run=$dry_run
    }
}

# generation, last run, drift and pending migrations at a glance
def "main status" []: nothing -> record {
    guarded status {
        # this status run has its own file already; the interesting one is the last real run before it
        let last = ls (runs-dir) | where name !~ $env.DOT_RUN_ID | sort-by name | last
        let records = open --raw $last.name | lines | each { from json }
        {
            generation: (^git -C $REPO log -1 --format=%s | str trim)
            build: (build)
            last_run: ($last.name | path basename | str replace ".jsonl" "")
            errors: ($records | where level in [ERROR PANIC] | length)
            drift: (main diff | length)
            migrations_pending: (migrations-pending $REPO user | get id)
            system_pending: (try { open --raw (pending-file) | lines | uniq } catch { [] })
            preserved: (preserve-report)
        }
    }
}

# a run's records (default the last) by module and level; --trace the span tree with timings
def "main log" [run?: string, --module: string, --level: string = "INFO", --trace]: nothing -> any {
    let file = if $run == null { ls (runs-dir) | sort-by name | last | get name } else { runs-dir | path join $"($run).jsonl" }
    let records = open --raw $file | lines | each { from json }
    if $trace {
        let spans = $records | where kind? == span
        let ends = $spans | where phase == end | reduce --fold {} {|e, acc| $acc | upsert $e.span $e }
        let parents = $spans | where phase == begin | reduce --fold {} {|b, acc| $acc | upsert $b.span $b.parent }
        return ($spans | where phase == begin | each {|b|
            mut depth = 0
            mut up = $b.parent
            while ($up | is-not-empty) { $depth += 1; $up = $parents | get --optional $up | default "" }
            let end = $ends | get --optional $b.span
            $"('' | fill --width ($depth * 2))($b.target) ($end.ms? | default '?')ms ($end.outcome? | default 'open')"
        } | str join "\n")
    }
    let rank = [TRACE DEBUG INFO WARN ERROR PANIC] | enumerate | where item == ($level | str uppercase) | get 0.index
    $records | where {|r| ([TRACE DEBUG INFO WARN ERROR PANIC] | enumerate | where item == $r.level | get 0.index) >= $rank }
    | where {|r| $module == null or $r.module == $module } | select time level module msg
}

# which module and run wrote a path, or which module declares a package
def "main explain" [thing: string]: nothing -> any {
    guarded explain {
        let target = if ($thing | str contains "/") { $thing | path expand } else { $thing }
        let owners = glob (state-dir | path join modules **/*.nuon) | each {|f|
            let st = open $f
            $st.outputs | where target == $target | each { {module: ($f | path dirname | path relative-to (state-dir | path join modules)), verb: ($f | path parse | get stem), output: $in, run: $st.run, time: $st.time} }
        } | flatten
        let ctx = pipeline-load $REPO user
        let declares = $ctx.modules | where {|m| $thing in $m.meta.packages.pacman } | get id
        {owners: $owners, packages_declared_by: $declares}
    }
}

def gate-report [what: string, findings: list<string>, notes: list<string>]: nothing -> nothing {
    $notes | each { print $"dot test: ($in)" } | ignore
    if ($findings | is-not-empty) {
        print ($findings | str join "\n")
        exit 1
    }
    print $"dot test: ($what) clean"
}

# the static gates (lint, check, fmt) and the vm test (run, logs, drill, shot, type, destroy)
def "main test" []: nothing -> nothing { help main test }

# static checks: module refs, layer rules, ~/sync writes, generated files, *.test.sh
def "main test lint" []: nothing -> nothing { gate-report lint (gate-lint) [] }

# every formatter and linter, verified (the sync gate), plus palette.nu against Palette.js
def "main test check" []: nothing -> nothing {
    let tools = gate-tools false
    let palette = gate-palette
    gate-report check ($tools.findings ++ $palette.findings) ($tools.notes ++ $palette.notes)
}

const VM_NAME = "archlinux-test"

# end-to-end vm test from the iso through the whole chain; hours; local tree unless --master
def "main test run" [--iso: path, --platform: string, --user: string, --master, --name: string = $VM_NAME]: nothing -> nothing {
    guarded test {
        let problems = gate-lint
        if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
        vm-run $name ($iso | default ($nu.home-dir | path join downloads archlinux-x86_64.iso)) ($platform | default $PLATFORM) ($user | default $USER) $master
    }
}

# pull the stage logs, FAILURES.* and every *.log of the test vm to ~/.cache/vm-test/<name>/logs
def "main test logs" [--name: string = $VM_NAME]: nothing -> nothing { guarded test { vm-logs $name } }

# a drill on a passed run's vm: egress or rollback; both change the vm
def "main test drill" [drill: string, --user: string, --name: string = $VM_NAME]: nothing -> nothing {
    guarded test { vm-drill $name $drill ($user | default $USER) }
}

# screenshot of the test vm to ~/.cache/vm-test/<name>/screen.png
def "main test shot" [--name: string = $VM_NAME]: nothing -> nothing { guarded test { print (screenshot $name) } }

# type text on the test vm's console (\n for enter)
def "main test type" [text: string, --layout: string = "de", --name: string = $VM_NAME]: nothing -> nothing {
    guarded test { vm-type $name $text $layout }
}

# delete the test vm and its disk
def "main test destroy" [--name: string = $VM_NAME]: nothing -> nothing { guarded test { vm-destroy $name } }

# secrets: the git-crypt worktree behind the yubikey; init enrolls a key, seal re-seals
def "main secrets" []: nothing -> nothing { help main secrets }
def "main secrets init" [...steps: string]: nothing -> nothing { guarded secrets { yubikey-init ...$steps } }
def "main secrets seal" []: nothing -> nothing { guarded secrets { yubikey-seal } }
# pull and unlock secrets/ with a touch of the yubikey, or --identity <age file> without one
def "main secrets unlock" [--identity: path]: nothing -> nothing { guarded secrets { yubikey-unlock --identity=$identity } }
def "main secrets lock" []: nothing -> nothing { guarded secrets { yubikey-lock } }

# the secrets audit: what is due for rotation or a recovery drill; --brief for the login notice
def "main audit" [--brief]: nothing -> nothing { guarded audit { audit-run --brief=$brief } }
def "main audit rotated" [...paths: path]: nothing -> nothing { guarded audit { audit-rotated ...$paths } }
def "main audit drilled" []: nothing -> nothing { guarded audit { audit-drilled } }
def "main audit remind" []: nothing -> nothing { guarded audit { audit-remind } }

# every formatter applied, then what is left
def "main test fmt" []: nothing -> nothing {
    let tools = gate-tools true
    $tools.notes | each { print $"dot test: ($in)" } | ignore
    if ($tools.findings | is-empty) { print "dot test: formatted, no findings"; return }
    print ($tools.findings | str join "\n")
    print $"dot test: formatted; ($tools.findings | length) finding\(s\) remain \(run after installing any missing tool\)"
}

def module-hash [dir: path]: nothing -> string {
    glob $"($dir)/**/*" --no-dir | where not ($it | str ends-with ".log") | sort | each {|f| $"($f) (open --raw $f | hash sha256)" } | str join "\n" | hash sha256
}

def backup-native [ctx: record, m: record]: nothing -> record {
    let r = modules-eval [$m] backup {$m.id: $m.cfg} [] --private=($m.meta.backup?.secrets? | default false) | first
    if not $r.ok { log-warn $"backup: ($m.id) failed, its state is from an older run: ($r.error)" }
    $r
}

# copy live app state into the repo; --roundtrip backs up, restores, backs up and compares
def "main backup" [--roundtrip]: nothing -> nothing {
    guarded backup {
        let ctx = pipeline-load $REPO user
        let locked = not (secret-is-plaintext ($REPO | path join secrets pgp_privatekey.asc))
        let mods = $ctx.modules | where {|m| "backup" in $m.native and $m.cfg.enable }
        let secret = {|m| $m.meta.backup?.secrets? | default false }
        if not $roundtrip {
            let skipped = $mods | where {|m| (do $secret $m) and $locked }
            with-env (platform-env $ctx.platform) { $mods | where id not-in $skipped.id | each {|m| backup-native $ctx $m } | ignore }
            if ($skipped | is-not-empty) { log-warn $"backup: secrets is locked, skipped ($skipped.id | str join ' ')" }
            return
        }
        for m in ($mods | where {|m| not (do $secret $m) }) {
            backup-native $ctx $m | ignore
            let before = module-hash $m.dir
            let home = mktemp --directory
            let env_home = {HOME: $home, XDG_CONFIG_HOME: $"($home)/.config", XDG_DATA_HOME: $"($home)/.local/share", XDG_STATE_HOME: $"($home)/.local/state", XDG_CACHE_HOME: $"($home)/.cache"}
            let restored = with-env $env_home {
                let step = if "restore" in $m.native { [restore] } else { [link] }
                (^nu --no-config-file ($REPO | path join scripts dot.nu) ...(if $step.0 == "link" { [link $m.id] } else { [restore $m.id] }) | complete).exit_code == 0
            }
            let again = with-env $env_home { backup-native $ctx $m }
            rm --recursive --force $home
            if not ($restored and $again.ok and (module-hash $m.dir) == $before) { error make {msg: $"backup: ($m.id) round trip changed the module or failed"} }
            log-info $"backup: ($m.id) round trip ok"
        }
    }
}

# run one module's restore verb (state its link does not already restore)
def "main restore" [mod: string]: nothing -> nothing {
    guarded restore {
        let ctx = pipeline-load $REPO user
        let m = $ctx.modules | where id == $mod | get --optional 0
        if $m == null or "restore" not-in $m.native { error make {msg: $"($mod) has no restore verb"} }
        let r = with-env (platform-env $ctx.platform) { modules-eval [$m] restore {$m.id: $m.cfg} [] } | first
        if not $r.ok { error make {msg: $"restore ($mod): ($r.error)"} }
    }
}
# back up, commit the next signed generation and push; --no-verify skips the gates
def "main sync" [--no-verify]: nothing -> nothing { guarded sync { sync-run $REPO --no-verify=$no_verify } }
# health of this machine: failures, pending applies, drift, secrets, backups; --brief for the login notice
def "main doctor" [--brief]: nothing -> nothing { guarded doctor { doctor-run --brief=$brief } }

# packages and units that differ between machines
def "main drift" []: nothing -> nothing { guarded drift { drift-view } }
# this machine's drift report
def "main drift report" []: nothing -> nothing { guarded drift { drift-report | print -n } }
# publish this machine's report into secrets/drift/<host> when it changed
def "main drift publish" []: nothing -> nothing { guarded drift { drift-publish } }

# install a machine from the Arch ISO or set up a fresh WSL distro
def "main bootstrap" [platform: string = ""]: nothing -> nothing {
    guarded bootstrap { bootstrap-run $REPO $platform }
}

# one stage of the unattended install chain (dotfiles-stage.service)
def "main stage" []: nothing -> nothing {
    guarded stage { stage-run $REPO }
}

# download a pinned file, verify its sha256, put it in place; --extract <member> or .
def "main fetch file" [url: string, sha256: string, dest: path, --mode: string = "644", --extract: string]: nothing -> nothing {
    guarded fetch { fetch-file-run $url $sha256 $dest --mode $mode --extract=$extract }
}

# <dir> checked out at exactly <commit>, submodules too
def "main fetch git" [url: string, commit: string, dir: path]: nothing -> nothing {
    guarded fetch { fetch-git-run $url $commit $dir }
}

# preserved copies older than <days>, after a yes
def "main prune" [days: int]: nothing -> nothing {
    guarded prune { preserve-prune $days }
}
