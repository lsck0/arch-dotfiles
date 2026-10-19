#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname | path dirname
const LIB = $REPO | path join scripts lib
use ($LIB | path join log.nu) *
use ($LIB | path join cli.nu) [concat jobs build guarded]
use ($LIB | path join usage.nu) [die]
use ($LIB | path join complete.nu) [command-table module-ids option-keys option-values theme-names run-ids]
use ($LIB | path join state.nu) [SYSTEM_REPO SYSTEM_STATE state-dir]
use ($LIB | path join platform.nu) [platform-load platform-env]
use ($LIB | path join profile.nu) [profile-has]
use ($LIB | path join options.nu) [OPTION_ENABLE options-schema option-value-errors options-notify options-to-nuon]
use ($LIB | path join modules.nu) [modules-graph modules-packages modules-eval]
use ($LIB | path join pipeline.nu) [pipeline-load pipeline-plan pipeline-apply]
use ($LIB | path join converge.nu) [state-read observe decls-check plan-module recorded-hashes apply-module state-write output-file-state]
use ($LIB | path join written.nu) [written-begin written-prune written-end preserve-report tty-confirm]
use ($LIB | path join ledger.nu) [ledger-units ledger-get ledger-set packages-convergence]
use ($LIB | path join migrate.nu) [migrations-run migrations-pending]
use ($LIB | path join sandbox.nu) [plan-sandbox plan-snapshot-units plan-report plan-end]
use ($LIB | path join gate.nu) [gate-lint gate-tools gate-palette]
use ($LIB | path join vm.nu) [USER PROFILE PLATFORM vm-run vm-logs vm-drill vm-destroy vm-type screenshot]
use ($LIB | path join yubikey.nu) [yubikey-init yubikey-seal yubikey-unlock yubikey-lock]
use ($LIB | path join audit.nu) [audit-run audit-rotated audit-drilled]
use ($LIB | path join drift.nu) [drift-view]
use ($LIB | path join doctor.nu) [doctor-run doctor-checks]
use ($LIB | path join system.nu) [system-pack system-archive ENTRY]
use ($LIB | path join wallpaper.nu) [wallpaper-set wallpaper-random wallpaper-pick]
use ($LIB | path join rollback.nu) [rollback-run]
use ($LIB | path join sync.nu) [sync-pull sync-commit sync-can-sign]

const INTERNAL = $LIB | path join internal.nu
const FAILURES = "FAILURES.config"
const EXIT_SYSTEM_PENDING = 3
const FAILURES_INSTALL = "FAILURES.install"
# dot internal stage retries an abort, moves on from a run that only recorded failures
const EXIT_ABORTED = 2
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
const THEME_STAMP_PATHS = [configs/core/wallust themes 'configs/*/*/mod.nu' scripts/lib/wallpaper.nu]
const THEME_DEFAULT_WALLPAPER = "alena-aenami-cover-art-007-3.jpg"

def summary [results: table]: nothing -> nothing {
    let outcomes = $results | get outcomes | concat
    let counts = $outcomes | group-by kind | items {|k, v| $"($v | length) ($k)" } | str join ", "
    let busy = $results | where {|r| ($r.outcomes | is-not-empty) or ($r.log | str trim | is-not-empty) } | get id | uniq
    let skipped = ($results.id | uniq | length) - ($busy | length)
    log-info $"($results.id | uniq | length) modules, ($skipped) unchanged(if ($counts | is-empty) { '' } else { $', ($counts)' })" {kind: summary}
    let slow = $results | sort-by ms --reverse | first 5 | each { $"($in.ms / 1000 | math round --precision 1)s ($in.id)" } | str join ", "
    log-debug $"slowest: ($slow)"
}

# <mods> the ones asked for: each that has no row here gets its reason
def plan-print [planned: table, verb: string, modules: table = [], mods: list<string> = []]: nothing -> nothing {
    let busy = $planned | where {|m| $m.error != null or ($m.actions | any { $in.kind != skip }) }
    for m in $busy {
        if $m.error != null {
            print $"($m.id): error: ($m.error)"
        } else {
            print $m.id
            $m.actions | where kind != skip | each {|a| print $"  ($a.kind | fill --width 8) ($a.target)(if ($a.reason | is-empty) { '' } else { $'  (($a.reason))' })" } | ignore
        }
    }
    let layer = if $verb == "system" { "system" } else { "user" }
    let absent = $mods | where $it not-in $planned.id | each {|id|
        let m = $modules | where id == $id | first
        if not $m.cfg.enable { $"($id): disabled on this machine" } else { $"($id): no ($layer) layer" }
    }
    $absent | each { print $in } | ignore
    if ($busy | is-empty) and ($absent | is-empty) { print (if $verb == "unlink" { "nothing to undo" } else { "nothing to apply" }) }
}

def --env link-run [mods: list<string>, force: bool, plan: bool]: nothing -> table {
    let ctx = pipeline-load $REPO user
    # zshrc sets it only interactively; mason's go would create ~/go
    $env.GOPATH = $nu.home-dir | path join .go
    let planned = pipeline-plan $ctx link $mods $force
    if $plan {
        plan-print $planned link $ctx.modules $mods
        return []
    }
    let full = $mods | is-empty
    $env.DOT_FULL_RUN = $full
    failures-open
    if $full { written-begin }
    let results = with-env (platform-env $ctx.platform) { pipeline-apply $ctx $planned link (jobs) }
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

# false when the run left a failure; FAILURES.config always holds the last full run's
def failures-publish [results: table]: nothing -> bool {
    let owned = $env.DOT_FAILURES_OWNED? == true
    let failures = if $owned and ($env.FAILURES_FILE | path exists) { open --raw $env.FAILURES_FILE | str trim } else { "" }
    if ($failures | is-not-empty) {
        let published = $REPO | path join $FAILURES
        $"($failures)\n" | save --force $"($published).($env.DOT_RUN_ID)"
        mv --force $"($published).($env.DOT_RUN_ID)" $published
        print "=== FAILED ==="
        print $failures
        return false
    }
    if ($results | any { not $in.ok }) { return false }
    if $owned and ($env.DOT_FULL_RUN? == true) { rm --force ($REPO | path join $FAILURES) }
    true
}

def finish [results: table]: nothing -> nothing {
    run-journal
    if not (failures-publish $results) { exit 1 }
}

const USAGE = "dot: this machine as code. `dot sync` brings it to what the repo prescribes and records it

  sync [--no-push]                pull, migrate, install, apply, back up, commit the signed generation, push
  apply [mod...]                  converge now, no git: system layer, then user layer; modules: their user layer
    --user | --system             one layer
    --packages                    declared packages, flatpak and nix instead, removals after a yes
  plan [mod...]                   what an apply would do; --order the run order, --modules every module
  status [--brief]                generation, pending work, failures, drift, secrets, backups
  set [mod[.key] [value]]         options: every set one, a module's, one; a value sets it, --default resets it
  theme [name|random]             wallpaper and theme, fzf without a name
  module adopt|unlink|remove|restore
  log [run] | explain <thing>     a run's records | who wrote a path, who declares a package
  secrets unlock|lock|init|seal|audit
  rollback [gen]                  an earlier generation
  test lint|check|fmt|run|...     the gates and the vm test

  --no-system on sync, apply, set: only the user part, same as DOT_SYSTEM=skip
  dot <command> --help for its flags"

# retired names, so an unknown command can point at its successor
const COMMANDS_MOVED = {
    update: sync, link: "apply --user", system: "apply --system", install: "apply --packages", gen: "internal gen"
    options: set, unlink: "module unlink", remove: "module remove", adopt: "module adopt", restore: "module restore"
    diff: plan, watch: "internal watch"
}
const LOG_LEVELS = [TRACE DEBUG INFO WARN ERROR PANIC]

# this machine as code; `dot sync` brings it to what the repo prescribes
def --wrapped main [...args: string]: nothing -> nothing {
    let word = $args | get --optional 0
    if $word == null or $word in [--help -h help] {
        print $USAGE
        return
    }
    let moved = $COMMANDS_MOVED | transpose name now | where name == $word | get --optional 0.now
    die --misuse $"unknown command '($word)'(if $moved == null { ', dot lists them' } else { $', it is dot ($moved) now' })"
}

# what an apply would do, touching nothing
def "main plan" [
    ...mods: string@module-ids
    --system   # the system layer
    --sandbox  # also a real run under bubblewrap, for its write set
    --force    # as an apply --force would
    --order    # each enabled module with its level and what it waits for
    --modules  # every module: kind, verbs, whether this machine runs it
    --json     # --order or --modules as json
]: nothing -> any {
    if $order or $modules {
        return (guarded plan {
            let layer = if $system { "system" } else { "user" }
            let ctx = pipeline-load $REPO $layer
            let rows = if $order {
                let verb = if $system { "system" } else { "link" }
                modules-graph $REPO ($ctx.modules | where {|m| $verb in $m.verbs and $m.cfg.enable }) | select level id after
                | update after { str join " " }
            } else {
                $ctx.modules | each {|m|
                    {id: $m.id, kind: (if ($m.native | is-empty) { "packages" } else { "native" }), verbs: ($m.verbs | str join " "), enabled: $m.cfg.enable, packages: ($m.meta.packages.pacman | length)}
                }
            }
            if $json { $rows | to json } else { $rows }
        })
    }
    guarded plan {
        if $system {
            let ctx = pipeline-load $REPO system
            plan-print (pipeline-plan $ctx system $mods $force) system $ctx.modules $mods
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
            print $"installed, declared by no module \(($extra.remove | length)\): ($extra.remove | str join ' ')\n  dot apply --packages removes them after a yes"
        }
        if $sandbox {
            let dir = mktemp --directory
            plan-snapshot-units $dir user
            let roots = [$nu.home-dir] | append (if ($REPO | str starts-with $nu.home-dir) { [] } else { [$REPO] })
            let status = with-env {FAILURES_FILE: ($dir | path join FAILURES)} {
                plan-sandbox $dir $roots [($REPO | path join scripts dot.nu) apply --user ...$mods]
            }
            print (plan-report $dir ($dir | path join FAILURES))
            plan-end $dir
            if $status != 0 { log-err $"the sandboxed run itself failed \(($status)\), the write set above is partial" }
        }
    }
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
    # before the re-exec: its pty stdin would look like a person even under dot internal stage's </dev/null
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

# a skipped root part is work left, not success: recorded for dot plan and status, the run exits 3
def --env system-skipped [what: string, pending: bool]: nothing -> nothing {
    if $pending { $"($what)\n" | save --append (pending-file) }
    log-note $"system part pending \(DOT_SYSTEM=skip\): ($what)"
    $env.DOT_SYSTEM_PENDING = true
}

def --env pending-exit []: nothing -> nothing {
    if $env.DOT_SYSTEM_PENDING? == true { exit $EXIT_SYSTEM_PENDING }
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
    if $system and (system-allowed) {
        if (system-run config --snapshot --force=$force) == 0 { rm --force (pending-file) } else { system-failed config }
    } else if $system and (admin) {
        system-skipped "system layer" true
    }
    if $user { link-run [] $force false } else { [] }
}

def flag [name: string, on: bool]: nothing -> list<string> {
    if $on { [$"--($name)"] } else { [] }
}

# converge now, no git: system layer from the root-owned copy, then user layer; modules: only their user layer
def "main apply" [
    ...mods: string@module-ids
    --user       # the user layer alone
    --system     # the system layer alone
    --packages   # every declared package, flatpak and nix after a snapshot, then removals after a yes
    --force      # overwrite drift, the live copy preserved aside
    --yes        # with --packages: remove packages no module declares without asking
    --no-system  # only the user part, same as DOT_SYSTEM=skip
]: nothing -> nothing {
    if $no_system { $env.DOT_SYSTEM = "skip" }
    let one = if $user and $system { "" } else if $user or ($mods | is-not-empty) { "user" } else if $system { "system" } else { "" }
    if ($mods | is-not-empty) and $system { die --misuse "apply: modules converge their user layer, --system takes none" }
    if $packages {
        if ($mods | is-not-empty) { die --misuse "apply --packages takes no modules" }
        if $one == "system" { die --misuse "apply --packages: both layers, or --user alone" }
        pty-log install ([apply --packages] ++ (flag user ($one == "user")) ++ (flag yes $yes))
        guarded apply {
            let status = install-run ($one == "user") $yes true
            if $status != 0 { exit $status }
            pending-exit
        }
    }
    match $one {
        "user" => { guarded apply { link-run $mods $force false | finish $in } }
        "system" => {
            pty-log config ([apply --system] ++ (flag force $force))
            guarded apply {
                if not (admin) { error make {msg: "apply --system: the system layer is root's, and this login is not in wheel"} }
                apply-run true false $force | finish $in
                pending-exit
            }
        }
        _ => {
            pty-log config ([apply] ++ (flag force $force))
            guarded apply {
                apply-run true true $force | finish $in
                pending-exit
            }
        }
    }
}

# one module by hand: adopt, unlink, remove, restore
def "main module" []: nothing -> nothing { help main module }

# reverse a native module's last apply; files changed since stay, originals come back
def "main module unlink" [mod: string@module-ids]: nothing -> nothing {
    guarded unlink { unlink-run $mod | finish $in }
}

def --env unlink-run [mod: string]: nothing -> table {
    let ctx = pipeline-load $REPO user
    let m = $ctx.modules | where id == $mod | get --optional 0
    if $m == null { error make {msg: $"no module ($mod); dot plan --modules lists them"} }
    if ($m.native | is-empty) { error make {msg: $"($mod) only declares packages, there is nothing to unlink"} }
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
def "main module remove" [mod: string@module-ids, --machine, --yes]: nothing -> nothing {
    guarded remove {
        let ctx = pipeline-load $REPO user
        let m = $ctx.modules | where id == $mod | get --optional 0
        if $m == null { error make {msg: $"no module ($mod); dot plan --modules lists them"} }
        let dependents = $ctx.modules | where {|d| $d.cfg.enable and $mod in $d.meta.deps } | get id
        if ($dependents | is-not-empty) { error make {msg: $"($dependents | str join ', ') depend on ($mod), remove those first"} }
        if ($m.native | is-not-empty) { unlink-run $mod | ignore }
        option-write $mod enable false $machine | ignore
        let others = modules-packages $REPO ($ctx.modules | where id != $mod) $ctx.platform | get pacman
        let only = $m.meta.packages.pacman | where $it not-in $others
        if ($only | is-not-empty) {
            print $"packages only ($mod) declares: ($only | str join ' ')"
            if not (system-allowed) {
                print $"remove them as root: pacman -Rns ($only | str join ' ')"
                if (admin) { system-skipped $"packages of ($mod)" false }
            } else if $yes or (tty-confirm "remove them?") { ^sudo pacman -Rns ...$only }
        }
        pending-exit
    }
}

# carry a live edit of a managed copy back into the module's source, so the next apply keeps it
def "main module adopt" [file: path]: nothing -> nothing {
    guarded adopt {
        let target = $file | path expand
        let ctx = pipeline-load $REPO user
        let planned = pipeline-plan $ctx link [] true
        let found = $planned | get actions | concat | where target == $target and decl.kind == file | get --optional 0
        if $found == null { error make {msg: $"($target) is no file a module copies; dot status lists the changed ones"} }
        if $found.decl.source == null { error make {msg: $"($target) is rendered by ($found.module), adopt it by editing its template"} }
        ^cp $target $found.decl.source
        log-info $"($target) -> ($found.decl.source | path relative-to $REPO)"
    }
}

# run one module's restore verb (state its link does not already restore)
def "main module restore" [mod: string@module-ids]: nothing -> nothing {
    guarded restore {
        let ctx = pipeline-load $REPO user
        let m = $ctx.modules | where id == $mod | get --optional 0
        if $m == null or "restore" not-in $m.native { error make {msg: $"($mod) has no restore verb"} }
        let r = with-env (platform-env $ctx.platform) { modules-eval [$m] restore {$m.id: $m.cfg} [] } | first
        if not $r.ok { error make {msg: $"restore ($mod): ($r.error)"} }
    }
}

# flatpak in user scope: a system deploy needs a polkit agent the unattended chain lacks
def install-user [declared: record]: nothing -> nothing {
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
    # packages are no apply's work, so nothing goes to the pending file; the exit says it
    if not $user and not $system and (admin) { system-skipped "packages" false }
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

def toggle-script [name: string]: nothing -> path {
    $REPO | path join scripts toggles $"toggle-($name).nu"
}

def option-runtime [spec: record]: nothing -> any {
    if ($spec.toggle? | default null) == null { return null }
    try { ^(toggle-script $spec.toggle) get | str trim } catch { null }
}

def options-list [mod: any, json: bool]: nothing -> any {
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

def option-target [target: string]: nothing -> record {
    let parts = $target | parse --regex '^(?<mod>.+)\.(?<key>[a-z][a-z0-9_]*)$' | get --optional 0
    if $parts == null { error make {msg: $"($target): want <group/module>.<option>"} }
    $parts
}

# a null value removes the key, so the layer below applies
def option-write [mod: string, key: string, value: any, machine: bool]: nothing -> record {
    let ctx = pipeline-load $REPO user
    let m = $ctx.modules | where id == $mod | get --optional 0
    if $m == null { error make {msg: $"no module ($mod); dot plan --modules lists them"} }
    let spec = options-schema $m | get --optional $key
    if $spec == null { error make {msg: $"($mod) has no option ($key); dot set ($mod) lists them"} }
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

# the value is stored either way; a failed apply is reported to the settings window and exits 1
def option-apply [target: string, set: record]: nothing -> nothing {
    mut results = []
    mut toggle_error = ""
    mut runtime: any = null
    match $set.spec.apply {
        "live" => {
            if "apply" in $set.module.native {
                let ctx = pipeline-load $REPO user
                $results = pipeline-apply $ctx (pipeline-plan $ctx apply [$set.module.id] true) apply 1
            } else if ($set.spec.toggle? | default null) != null {
                let argv = match ($set.value | describe) { "bool" => [(if $set.value { "on" } else { "off" })], _ => [set ($set.value | into string)] }
                let toggled = ^(toggle-script $set.spec.toggle) ...$argv | complete
                if ($toggled.stdout | str trim | is-not-empty) { print ($toggled.stdout | str trim) }
                if $toggled.exit_code != 0 {
                    $toggle_error = $"toggle-($set.spec.toggle) exited ($toggled.exit_code): ($toggled.stderr | str trim | lines | last 1 | str join '')"
                }
                $runtime = option-runtime $set.spec
            }
        }
        $apply => {
            # a disabled module is skipped by link, so turning it off has to undo it here
            if ($target | str ends-with $".($OPTION_ENABLE)") and $set.value == false and ($set.module.native | is-not-empty) {
                $results = unlink-run $set.module.id
                print $"note: ($set.module.id) unlinked; dot module remove ($set.module.id) also drops its packages"
            } else if "link" in $set.module.verbs { $results = link-run [$set.module.id] false false }
            # machine options reach the system verb only through the root-owned copy
            if $set.spec.scope == "machine" and "system" in $set.module.verbs and (admin) { system-part $target }
            if $apply != "relink" {
                log-note $"($target) takes effect after a ($apply)"
            }
        }
    }
    let failed = $results | where not ok | each {|r| $"($r.id): ($r.error | default 'failed')" }
    let error = if ($failed | is-not-empty) { $"stored, the apply failed: ($failed | str join '; ')" } else if $toggle_error != "" { $"stored, ($toggle_error)" } else { null }
    options-notify $target $set.value $set.source $runtime --error $error
    if $error != null { error make {msg: $"($target): ($error)"} }
    pending-exit
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

# options: every one off its default, a module's, one; a value sets it, --default resets it
def "main set" [
    target?: string@option-keys
    ...value: any@option-values  # nuon or json, validated, stored, applied as the option says
    --default    # reset it, the layer below applies
    --machine    # the platform's value, for a machine option
    --json       # with schema and live state, for the settings window
    --no-system  # only the user part, same as DOT_SYSTEM=skip
]: nothing -> any {
    if $no_system { $env.DOT_SYSTEM = "skip" }
    guarded set {
        # a rest, so a given null (reset, as the settings window sends it) differs from none
        if ($value | length) > 1 { error make {msg: "dot set <module>.<option> <value>: one value, quote a list"} }
        let given = $value | is-not-empty
        let value = $value | get --optional 0
        let ids = if $target == null { [] } else { pipeline-load $REPO user | get modules.id }
        if $target == null or $target in $ids {
            if $default or $given { error make {msg: "dot set <module>.<option> <value>, or --default"} }
            return (options-list $target $json)
        }
        let t = option-target $target
        if $json { return (options-list $t.mod true) }
        if $default {
            if $given { error make {msg: "dot set --default takes no value"} }
            option-apply $target (option-write $t.mod $t.key null $machine)
            return
        }
        if not $given {
            let row = options-list $t.mod false | where option == $t.key | get --optional 0
            if $row == null { error make {msg: $"no option ($target); dot set lists them"} }
            return $row
        }
        # nu passes true, 3 or [a b] typed; a string may still be nuon or json (the settings window)
        let parsed = if ($value | describe) != "string" { $value } else { try { $value | from nuon } catch { try { $value | from json } catch { $value } } }
        option-apply $target (option-write $t.mod $t.key $parsed $machine)
    }
}

# every recorded output that no longer holds; pending: the next apply puts it back without being told to
def managed-drift []: nothing -> table {
    glob (state-dir | path join modules **/*.nuon) | each {|f|
        let id = $f | path dirname | path relative-to (state-dir | path join modules)
        let outs = open $f | get outputs
        let seen = observe ($outs | where kind != unit | get target) ($outs | where kind == unit | get target) user
        $outs | each {|o|
            let obs = $seen.paths | get --optional $o.target
            let state = match $o.kind {
                "file" => (output-file-state $o $obs $REPO)
                "link" => (if $obs.link? != $o.source { "relinked" } else { null })
                "unit" => {
                    let now = $seen.units | get --optional $o.target
                    let held = match ($o.state? | default enabled) { "disabled" => ($now != "enabled"), $want => ($now == $want) }
                    if $held { null } else { $now | default missing }
                }
                _ => null
            }
            if $state == null { null } else { {module: $id, target: $o.target, drift: $state, pending: ($o.kind == "unit" or $state == "missing")} }
        } | compact
    } | flatten
}

# wallpaper and theme: fzf without a name, random for any
def "main theme" [
    wallpaper?: string@theme-names
    --sync  # wait for every theme verb
]: nothing -> nothing {
    guarded theme {
        match $wallpaper {
            null => (wallpaper-pick)
            "random" => (wallpaper-random --sync=$sync)
            _ => (wallpaper-set $wallpaper --sync=$sync)
        }
    }
}

def --env update-run [yes: bool]: nothing -> record {
    sync-pull $REPO
    migrations-run $REPO user | ignore
    let install = install-run false $yes true
    if $install == $EXIT_ABORTED { exit $EXIT_ABORTED }
    if (system-allowed) { ^sudo ($SYSTEM_REPO | path join $ENTRY) migrate } else if (admin) { system-skipped "system migrations" false }
    {install: $install, results: (apply-run true true false)}
}

# the one command: pull, snapshot, migrate, install, apply, back up app state, commit the signed generation, push
def "main sync" [
    --no-push    # stop after the apply: no backup, commit or push; a machine that does not sign always stops there
    --yes        # remove packages no module declares without asking
    --no-system  # only the user part, same as DOT_SYSTEM=skip
    --no-verify  # commit without the formatter, linter and gitleaks gates
]: nothing -> nothing {
    if $no_system { $env.DOT_SYSTEM = "skip" }
    guarded sync {
        let run = update-run $yes
        let clean = failures-publish $run.results
        if $no_push {
        } else if (sync-can-sign $REPO) {
            sync-commit $REPO --no-verify=$no_verify
        } else {
            log-note "this machine does not sign: applied, no backup, commit or push"
        }
        run-journal
        if not $clean or $run.install != 0 { exit 1 }
        pending-exit
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
        rollback-run $target --full=$full --dry-run=$dry_run
    }
}

def status-head []: nothing -> record {
    # this status run has its own file already; the interesting one is the last real run before it
    let last = ls (runs-dir) | where name ends-with ".jsonl" and name !~ $env.DOT_RUN_ID | sort-by name | last
    let records = if $last == null { [] } else { open --raw $last.name | lines | each { from json } }
    {
        generation: (^git -C $REPO log -1 --format=%s | str trim)
        build: (build)
        last_run: (if $last == null { "none" } else { $last.name | path basename | str replace ".jsonl" "" })
        errors: ($records | where level in [ERROR PANIC] | length)
        migrations_pending: (migrations-pending $REPO user | get id)
        system_pending: (try { open --raw (pending-file) | lines | uniq } catch { [] })
        preserved: (preserve-report)
    }
}

# generation, pending work, every health check; --brief the failures alone
def "main status" [
    --brief  # only the failed checks as "<check>: <text>"
    --json   # everything as one record, managed drift and checks included
]: nothing -> nothing {
    guarded status {
        if $brief {
            if (doctor-run --brief) { exit 1 }
            return
        }
        let head = status-head
        let drift = managed-drift
        if $json {
            let checks = doctor-checks
            print ($head | merge {drift: ($drift | where not pending | reject pending), pending_apply: ($drift | where pending | reject pending), checks: $checks} | to json)
            if ($checks | any { $in.level == "FAIL" }) { exit 1 }
            return
        }
        print $"($head.generation) at ($head.build.commit)(if $head.build.dirty { ', with edits' } else { '' })"
        print $"last run ($head.last_run), ($head.errors) errors"
        if ($head.migrations_pending | is-not-empty) { print $"migrations pending: ($head.migrations_pending | str join ' ')" }
        if ($head.system_pending | is-not-empty) { print $"system part pending: ($head.system_pending | str join ' '); dot apply runs it" }
        $drift | where pending | each { print $"pending apply: ($in.target) \(($in.module), ($in.drift)\); dot apply puts it back" } | ignore
        $drift | where not pending | each { print $"changed since its apply: ($in.target) \(($in.module), ($in.drift)\); dot module adopt or apply --force" } | ignore
        print ""
        let failed = doctor-run
        try { drift-view } catch { }
        if $failed { exit 1 }
    }
}

# a run's records (default the last) by module and level; --trace the span tree with timings
def "main log" [run?: string@run-ids, --module: string@module-ids, --level: string@[TRACE DEBUG INFO WARN ERROR PANIC] = "INFO", --trace]: nothing -> any {
    if ($level | str uppercase) not-in $LOG_LEVELS { die --misuse $"log: --level ($level), one of ($LOG_LEVELS | str join ' ')" }
    let file = if $run == null { glob (runs-dir | path join "*.jsonl") | sort | last } else { runs-dir | path join $"($run).jsonl" }
    if $file == null or not ($file | path exists) { error make --unspanned {msg: "dot log: no such run"} }
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

# static checks: module refs, layer rules, ~/sync writes, generated files, *.test.nu
def "main test lint" []: nothing -> nothing { gate-report lint (gate-lint) [] }

# every formatter and linter, verified (the sync gate), plus palette.nu against Palette.js
def "main test check" []: nothing -> nothing {
    let tools = gate-tools false
    let palette = gate-palette
    gate-report check ($tools.findings ++ $palette.findings) ($tools.notes ++ $palette.notes)
}

const VM_NAME = "archlinux-test"

# end-to-end vm test from the iso through the whole chain; hours; local tree unless --master
def "main test run" [--iso: path, --platform: string, --user: string, --profile: string, --master, --name: string = $VM_NAME]: nothing -> nothing {
    guarded test {
        let problems = gate-lint
        if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
        vm-run $name ($iso | default ($nu.home-dir | path join downloads archlinux-x86_64.iso)) ($platform | default $PLATFORM) ($user | default $USER) ($profile | default $PROFILE) $master
    }
}

# pull the stage logs, FAILURES.* and every *.log of the test vm to ~/.cache/vm-test/<name>/logs
def "main test logs" [--user: string, --name: string = $VM_NAME]: nothing -> nothing { guarded test { vm-logs $name ($user | default $USER) } }

# a drill on a passed run's vm: egress or rollback; both change the vm
def "main test drill" [drill: string@[egress rollback], --user: string, --name: string = $VM_NAME]: nothing -> nothing {
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

# the git-crypt worktree behind the yubikey
def "main secrets" []: nothing -> nothing { help main secrets }
# enroll a yubikey for secrets (every step, or the named ones)
def "main secrets init" [...steps: string]: nothing -> nothing { guarded secrets { yubikey-init ...$steps } }
# re-seal the git-crypt key to every enrolled key's recipient
def "main secrets seal" []: nothing -> nothing { guarded secrets { yubikey-seal } }
# pull and unlock secrets/ with a touch of the yubikey, or --identity <age file> without one
def "main secrets unlock" [--identity: path]: nothing -> nothing { guarded secrets { yubikey-unlock --identity=$identity } }
# lock secrets/ again
def "main secrets lock" []: nothing -> nothing { guarded secrets { yubikey-lock } }
# what is due for rotation or a recovery drill
def "main secrets audit" [--brief]: nothing -> nothing { guarded audit { audit-run --brief=$brief } }
# record <paths> as rotated today
def "main secrets audit rotated" [...paths: path]: nothing -> nothing { guarded audit { audit-rotated ...$paths } }
# record the recovery drill as done today
def "main secrets audit drilled" []: nothing -> nothing { guarded audit { audit-drilled } }

# every formatter applied, then what is left
def "main test fmt" []: nothing -> nothing {
    let tools = gate-tools true
    $tools.notes | each { print $"dot test: ($in)" } | ignore
    if ($tools.findings | is-empty) { print "dot test: formatted, no findings"; return }
    print ($tools.findings | str join "\n")
    print $"dot test: formatted; ($tools.findings | length) finding\(s\) remain \(run after installing any missing tool\)"
}

# plumbing for scripts, units and completion; dot internal --help
def --wrapped "main internal" [...args: string]: nothing -> nothing {
    if ($args | get --optional 0) in [complete completions] {
        $env.DOT_COMMANDS = command-table | to nuon
    }
    exec $nu.current-exe --no-config-file $INTERNAL ...$args
}
