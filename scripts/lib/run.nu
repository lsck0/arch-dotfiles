# The runs behind dot's commands, the system layer through root included.

const REPO = path self ../..
use log.nu *
use cli.nu [flag jobs root-runner state-lock-hold]
use state.nu [SYSTEM_REPO SYSTEM_STATE LIB_DIR state-dir save-atomic EXIT_ABORTED EXIT_PENDING xdg CONFIG_ISSUE file-trim]
use doctor.nu [doctor-checks]
use platform.nu [platform-load]
use profile.nu [profile-has]
use modules.nu [modules-packages]
use pipeline.nu [pipeline-load pipeline-plan pipeline-apply pending-save flatpak-installed nix-installed THEME_VERB_TIMEOUT NIX_FLAGS]
use converge.nu [state-read observe-outputs plan-module recorded-hashes apply-module state-write output-file-state unit-state-holds action-recorded dir-hidden]
use ledger.nu [ledger-units ledger-get ledger-set ledger-diff ledger-remove packages-convergence]
use migrate.nu [migrations-run migrations-pending]
use ../../configs/base/yubikey/yubikey.nu [yubikey-unlock]
use system.nu [system-pack system-archive system-secrets-digest entry-parses entry-takes-run ENTRY SYSTEM_STAGES SYSTEM_SECRETS_DIGEST RUN_ID]
use ../../configs/core/wallust/wallpaper.nu [wallpaper-set]
use cause.nu [cause-from-error cause-text failure-line failure-is-system names-shown SYSTEM_FIX]
use online.nu [network-online OFFLINE_PENDING]

export const INTERNAL = path self internal.nu
export const PIPELINE_CLI = path self pipeline-cli.nu
const FAILURES = "FAILURES.config"
const FAILURES_INSTALL = "FAILURES.install"
const FAILURES_PUBLISHED = $REPO | path join $FAILURES
const NIXPKGS = "github:NixOS/nixpkgs/b6c8664de9b6cc07fe5666a29f91884ba81197c4"
const FLATHUB = "https://dl.flathub.org/repo/flathub.flatpakrepo"
const LFS_FILTER = [
    -c "filter.lfs.clean=git-lfs clean -- %f" -c "filter.lfs.smudge=git-lfs smudge -- %f"
    -c "filter.lfs.process=git-lfs filter-process" -c filter.lfs.required=true
]
const FLATPAK_SYSTEM_EXPORTS = "/var/lib/flatpak/exports/share"
const FLATPAK_USER_EXPORTS = ".local/share/flatpak/exports/share"
const DATA_DIRS_DEFAULT = "/usr/local/share:/usr/share"
# the first root copy, before root has an entry of its own: system-unpack from this checkout, under root's lock
const SYSTEM_SEED = 'set -e; umask 022; mkdir -p "${1%/*}"; exec flock "${1%/*}/lock" /usr/bin/nu --no-config-file --stdin -I "$2" -c "use system.nu [system-unpack]; \$in | into binary | system-unpack \"$1\" $3"'
# bash, $0 the log and "$@" the command: its output goes to the terminal and the log alike, its exit code is the
# command's. No pty of its own: the command keeps the caller's terminal and session, where sudo finds its ticket.
const LOG_TEE = 'printf "%s: %s\n" "$(date --iso-8601=seconds)" "$*" > "$0"; "$@" 2>&1 | tee --append --ignore-interrupts -- "$0"; exit "${PIPESTATUS[0]}"'
# the doctor checks that must each report ok before a sync leaves root out
const IDLE_CHECKS = [failures config pending snapshot packages]
# what a sync names of one reason to enter root before it counts the rest
const DUE_SHOWN = 5
# the stage a root copy older than `apply --run` is replaced through: its `apply` knows install and config only. A sync
# goes through install, its own first step, so no config runs ahead of the upgrade.
const BRIDGE_STAGES = {install: install, config: config, sync: install}
# sudo's pty can take the interrupt alone; the exit code (130, or -2) carries it
const EXIT_INTERRUPTED = [130 -2]
# pkexec's own codes: the prompt was dismissed, the caller is not authorized
const PKEXEC_DECLINED = [126 127]
const CHECKUPDATES_TIMEOUT_S = 30
# checkupdates' exit code with nothing to upgrade
const CHECKUPDATES_NONE = 2
# what the palette is made from; a module's own theme verb is re-run by link-run's theme pass when its input changes,
# so a mod.nu edit is no reason to re-theme every module a second time
const THEME_STAMP_PATHS = [configs/core/wallust themes]
# a fresh install's theme: its wallpaper makes wallpaper.nu apply its palette
const THEME_DEFAULT = path self ../../themes/shien.json

def summary [results: table]: nothing -> nothing {
    let outcomes = $results | get outcomes | flatten
    let counts = $outcomes | group-by kind | items {|k, v| $"($v | length) ($k)" } | str join ", "
    let busy = $results | where {|r| ($r.outcomes | is-not-empty) or ($r.log | str trim | is-not-empty) } | get id | uniq
    let waiting = $results | where pending? != null | get id | uniq
    let skipped = ($results.id | uniq | length) - ($busy | length) - ($waiting | length)
    let held = if ($waiting | is-empty) { "" } else { $", ($waiting | length) pending" }
    log-info $"($results.id | uniq | length) modules, ($skipped) unchanged($held)(if ($counts | is-empty) { '' } else { $', ($counts)' })" {kind: summary}
    let slow = $results | sort-by ms --reverse | first 5 | each { $"($in.ms / 1000 | math round --precision 1)s ($in.id)" } | str join ", "
    log-debug $"slowest: ($slow)"
}

export def plan-print [planned: table, verb: string, modules: table = [], mods: list<string> = []]: nothing -> nothing {
    let busy = $planned | where {|m| $m.pending? != null or $m.error != null or ($m.actions | any { $in.kind != skip }) }
    for m in $busy {
        if $m.pending? != null {
            print $"($m.id): pending, ($m.pending)(if $m.error == null { '' } else { $'; error: ($m.error)' })"
        } else if $m.error != null {
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

# The user layer's plan; the module evaluations see GOPATH.
export def --env link-plan [ctx: record, mods: list<string>, force: bool]: nothing -> table {
    $env.GOPATH = xdg data go
    pipeline-plan $ctx link $mods $force
}

# The user layer's run; --user-only names the modules whose system part it leaves out, for a caller that runs none.
export def --env link-run [mods: list<string>, force: bool, --user-only]: nothing -> table {
    let ctx = pipeline-load $REPO user
    let planned = link-plan $ctx $mods $force
    let full = $mods | is-empty
    $env.DOT_FULL_RUN = $full
    failures-open
    let results = pipeline-apply $ctx $planned link (jobs)
    pending-save $planned.id $results --full=$full
    if ($results | any { $in.pending? != null }) { $env.DOT_SYSTEM_PENDING = true }
    let wallpaper = xdg cache wal wallpaper
    let waiting = $results | where pending? != null | get id
    # a gone module's revert row has no module left to theme, and pipeline-plan rejects its id
    let broken = $ctx.modules | where broken | get id
    let ids = $planned | where native and id in $ctx.modules.id and id not-in $broken and id not-in $waiting | get id
    # an empty id list means every module to pipeline-plan: a run that planned no link rows themes none
    let themed = if ($wallpaper | path exists) and ($ids | is-not-empty) {
        let real_wallpaper = ^readlink -f $wallpaper | str trim
        pipeline-plan $ctx theme $ids false [$real_wallpaper] --revert-all=$full | where native
        | pipeline-apply $ctx $in theme (jobs) [$real_wallpaper] --timeout $THEME_VERB_TIMEOUT
    } else { [] }
    if $full {
        for dir in [$nu.home-dir ($nu.home-dir | path join .local bin)] {
            ls -a $dir | where type == symlink | where {|l| not ($l.name | path exists) and ((^readlink $l.name) | str starts-with $"($REPO)/") } | each { rm $in.name } | ignore
        }
        let units = ledger-units $REPO ($ctx.modules | where cfg.enable) user
        $units.by_hand | each { log-info $"enabled by hand, not managed: ($in)" } | ignore
        theme-init
    } else if "core/wallust" in $mods {
        # a changed template is rendered by this run, not by the next theme switch
        theme-init
    }
    summary ($results ++ $themed)
    let system_left = $ctx.modules | where {|m| $m.id in $mods and "system" in $m.native } | get id
    if $user_only and ($system_left | is-not-empty) and $env.DOT_SYSTEM? != "skip" {
        log-note $"system part not applied: ($system_left | str join ' '); dot apply --system converges it"
    }
    $results ++ $themed
}

def theme-init []: nothing -> nothing {
    let files = ^git -C $REPO ls-files --cached --others --exclude-standard ...$THEME_STAMP_PATHS | lines | where $it != ""
        | each {|f| $REPO | path join $f } | where ($it | path exists) | uniq
    let stamp = ^sha1sum ...$files | ^sha1sum | str trim
    let cache = xdg cache wal
    let link = $cache | path join wallpaper
    if ($link | path exists) and (file-trim ($cache | path join .theme-stamp)) == $stamp { return }
    let wallpaper = if ($link | path exists) { ^readlink -f $link | str trim } else { open $THEME_DEFAULT | get wallpaper }
    wallpaper-set $wallpaper --sync
    $"($stamp)\n" | save --force ($cache | path join .theme-stamp)
}

def --env failures-open []: nothing -> nothing {
    if ($env.FAILURES_FILE? | is-empty) {
        $env.FAILURES_FILE = $env.DOT_RUN_FILE | str replace ".jsonl" ".failures"
        $env.DOT_FAILURES_OWNED = true
    }
}

# The modules a run carried through: every result of theirs ok and none pending, so their earlier failures are over.
def failures-cleared [results: table]: nothing -> list<string> {
    $results | group-by id | items {|id, rows| if ($rows | all {|r| $r.ok and $r.pending? == null }) { $id } } | compact
}

# Publishes the run's failures into published (the checkout's FAILURES.config), false when the run failed.
export def failures-publish [results: table, published: path = $FAILURES_PUBLISHED]: nothing -> bool {
    let owned = $env.DOT_FAILURES_OWNED? == true
    let failures = if $owned { file-trim $env.FAILURES_FILE } else { "" }
    let cleared = failures-cleared $results
    # a partial run adds to what earlier runs recorded instead of replacing it, but for the modules it carried through
    # a module's system line is over only when the system layer ran too
    let system_ran = $env.DOT_SYSTEM_RAN? == true
    let earlier = if ($published | path exists) {
        open --raw $published | lines | where {|l| ($l | split row " " | first) not-in $cleared or ((failure-is-system $l) and not $system_ran) }
    } else { [] }
    if ($failures | is-not-empty) {
        let kept = if ($env.DOT_FULL_RUN? != true) { $earlier } else if not $system_ran {
            $earlier | where {|l| failure-is-system $l }
        } else { [] }
        let failures = $kept | append ($failures | lines) | where ($it | str trim) != "" | uniq | str join "\n"
        $"($failures)\n" | save-atomic $published
        print "=== FAILED ==="
        print $failures
        return false
    }
    if ($results | any { not $in.ok }) { return false }
    if $owned and ($env.DOT_FULL_RUN? != true) and ($published | path exists) {
        let left = $earlier | where ($it | str trim) != ""
        if ($left | is-empty) { rm --force $published } else if ($left | length) != (open --raw $published | lines | where ($it | str trim) != "" | length) {
            $left | to text | save-atomic $published
        }
        return true
    }
    # a user-only run cannot vouch for the system layer: its earlier failures stay published until it runs again
    let system_stale = not $system_ran and ($published | path exists) and (open --raw $published | lines | any {|l| failure-is-system $l })
    if $owned and ($env.DOT_FULL_RUN? == true) {
        if not $system_stale { rm --force $published } else {
            # the user layer passed in full: only the system lines it cannot vouch for stay
            let system = open --raw $published | lines | where {|l| failure-is-system $l }
            $system | to text | save-atomic $published
        }
    }
    true
}

export def finish [results: table]: nothing -> nothing {
    run-journal
    if not (failures-publish $results) { exit 1 }
    config-banner-clear
}

# A failed config stage's login banner goes once a full apply, both layers run, left no FAILURES.config behind.
export def config-banner-clear []: nothing -> nothing {
    if not ($CONFIG_ISSUE | path exists) or $env.DOT_FULL_RUN? != true or $env.DOT_SYSTEM_RAN? != true { return }
    if ($FAILURES_PUBLISHED | path exists) { return }
    let runner = system-runner
    let r = ^$runner rm -f $CONFIG_ISSUE | complete
    if $r.exit_code != 0 { log-note $"($CONFIG_ISSUE) left in place: ($runner) rm exited ($r.exit_code)" }
}

export def admin []: nothing -> bool {
    ^id -nG | split row " " | any { $in == wheel }
}

export def system-allowed []: nothing -> bool {
    $env.DOT_SYSTEM? != "skip" and (admin)
}

# The argv that runs argv with its output teed into log, marked so the command does not wrap itself again.
export def log-tee-argv [log: path, argv: list<string>]: nothing -> list<string> {
    [env DOT_PTY_LOG=1 bash -c $LOG_TEE $log ...$argv]
}

# At a terminal, re-execs argv (this command) with its output also in <checkout>/<name>.log. The command then writes to
# a pipe, so its own colour is forced.
export def --env log-tee [name: string, argv: list<string>]: nothing -> nothing {
    if ($env.DOT_PTY_LOG? | is-not-empty) {
        $env.config.use_ansi_coloring = true
        return
    }
    if (is-terminal --stdout) { exec ...(log-tee-argv ($REPO | path join $"($name).log") $argv) }
}

export def --env tee-log [name: string, args: list<string>]: nothing -> nothing {
    if not (is-terminal --stdin) { $env.DOTFILES_UNATTENDED = "1" }
    log-tee $name [$nu.current-exe --no-config-file $PIPELINE_CLI ...$args]
}

# What runs the system layer: the caller's DOTFILES_ROOT_RUNNER, else root-runner's pick, else sudo.
def system-runner []: nothing -> string {
    $env.DOTFILES_ROOT_RUNNER? | default (root-runner) | default sudo
}

# Root's copy from this checkout, without an entry of root's to unpack it: only sudo at a terminal does that.
def system-seed [runner: string, head: string, why: string]: nothing -> nothing {
    if $runner != "sudo" { error make {msg: $"($SYSTEM_REPO) ($why), run dot apply at a terminal once"} }
    system-pack $REPO | ^sudo sh -c $SYSTEM_SEED sh $SYSTEM_REPO $LIB_DIR $head
}

# What root left in SYSTEM_STAGES for this run, null when it is another run's or unreadable.
def stages-read [run: string]: nothing -> any {
    let report = try { open $SYSTEM_STAGES } catch { null }
    if $report != null and $report.run? == $run and $run != "" { $report } else { null }
}

# Enters copy's `apply` for stage through runner, archive on its stdin: the entry's exit code. A copy whose entry does
# not take --run yet is first handed the argv it knows (BRIDGE_STAGES), which unpacks this checkout over it, and then
# entered as usual; an interrupted or aborted bridge, or one that left the old copy, is the result as it is.
export def entry-enter [runner: string, copy: path, head: string, stage: string, run: string, flags: list<string>, archive: binary]: nothing -> int {
    let entry = $copy | path join $ENTRY
    let enter = {|argv| try { $archive | ^$runner $entry apply $head ...$argv; 0 } catch {|e| $e.exit_code? | default 1 } }
    if not (entry-takes-run $copy) {
        let carrier = $BRIDGE_STAGES | get $stage
        log-note $"($copy) predates this entry protocol: replacing it through its own ($carrier) stage, then entering it again"
        let code = do $enter [$carrier ...$flags]
        if not (entry-takes-run $copy) { return (if $code == 0 { 1 } else { $code }) }
        if $code in ($EXIT_INTERRUPTED ++ [$EXIT_ABORTED]) { return $code }
    }
    do $enter [$stage ...(if $run == "" { [] } else { [--run $run] }) ...$flags]
}

# One root entry for a stage of system-apply.nu's `apply` (install, config, or sync for all of it): its exit code,
# what each step ended with ({stage, code, failures}, empty when root reported nothing) and root's run id.
def system-run [stage: string, --force, --yes]: nothing -> record {
    let runner = system-runner
    let head = ^git -C $REPO rev-parse HEAD | str trim
    let entry = $SYSTEM_REPO | path join $ENTRY
    if not ($entry | path exists) { system-seed $runner $head $"has no ($ENTRY) yet" }
    let run = $env.DOT_RUN_ID? | default "" | if $in =~ $RUN_ID { $in } else { "" }
    let flags = [--unattended=($env.DOTFILES_UNATTENDED? == "1")] ++ (flag force $force) ++ (flag yes $yes)
    let archive = system-archive $REPO (platform-load $REPO).facts.wireguard?
    let enter = {|| entry-enter $runner $SYSTEM_REPO $head $stage $run $flags $archive }
    mut code = do $enter
    # an entry that stopped parsing (a nushell upgrade, a broken tree shipped earlier) cannot unpack its own replacement
    if $code != 0 and (stages-read $run) == null and not (entry-parses $SYSTEM_REPO) {
        log-warn $"($entry) does not parse any more, replacing the root copy from this checkout"
        system-seed $runner $head $"holds an ($ENTRY) that does not parse"
        $code = do $enter
    }
    interrupted-exit $code
    let report = stages-read $run
    if $report != null { log-debug $"system ($stage): root's run ($report.root_run)" {kind: system-run, target: $report.root_run} }
    {code: $code, stages: ($report.stages? | default []), run: $report.root_run?}
}

# What a step of a root entry ended with: its own code, the entry's when root reported nothing, null when the entry
# never reached it.
export def stage-code [ran: record, stage: string]: nothing -> any {
    if ($ran.stages | is-empty) { return $ran.code }
    $ran.stages | where stage == $stage | get --optional 0.code
}

def interrupted-exit [code: int]: nothing -> nothing {
    if $code in $EXIT_INTERRUPTED {
        log-err "interrupted (ctrl+c) in the system layer: the run stopped, its later phases did not run"
        exit 130
    }
}

export def --env system-skipped [what: string, pending: bool, --why: string = "DOT_SYSTEM=skip"]: nothing -> nothing {
    if $pending { $"($what)\n" | save --append (pending-file) }
    log-note $"system part pending \(($why)\): ($what)"
    $env.DOT_SYSTEM_PENDING = true
}

# Whether a root entry never started: pkexec's prompt was dismissed or refused, so root reported nothing.
export def entry-declined [ran: record, runner: string]: nothing -> bool {
    $runner == "pkexec" and ($ran.stages | is-empty) and $ran.code in $PKEXEC_DECLINED
}

# A declined entry left the system layer as it was: pending, not failed, and this run cannot vouch for it.
def --env system-declined [what: string, pending: bool]: nothing -> nothing {
    system-skipped $what $pending --why "the pkexec prompt was dismissed or refused, root was not entered"
    $env.DOT_SYSTEM_RAN = false
}

export def --env pending-exit []: nothing -> nothing {
    if $env.DOT_SYSTEM_PENDING? == true { exit $EXIT_PENDING }
}

# An apply's end, called inside its guarded closure where the run's DOT_SYSTEM_PENDING is still visible: exit 1 on a
# failure, else 3 when anything is left pending.
export def --env apply-finish [results: table]: nothing -> nothing {
    finish $results
    pending-exit
}

# The FAILURES lines of a failed step of a root entry: root's own carry the causes. A root line naming no system module
# gets the layer as its subject, so a later user-only run still knows it for root's. Without one, the exit is the line.
export def stage-failures [ran: record, stage: string, runner: string]: nothing -> list<string> {
    let lines = $ran.stages | where stage == $stage | get --optional 0.failures | default []
    if ($lines | is-not-empty) { return ($lines | each {|l| if (failure-is-system $l) { $l } else { $"system layer ($l)" } }) }
    let log = if $ran.run == null { $SYSTEM_STATE | path join runs } else { $SYSTEM_STATE | path join runs $"($ran.run).jsonl" }
    let fix = $"($SYSTEM_FIX) at a terminal; root's run log: ($log)"
    [(failure-line $"system layer ($stage)" null $"($runner) ($ENTRY) exited (stage-code $ran $stage), root recorded no failure" --fix $fix)]
}

def system-failed [ran: record, stage: string]: nothing -> nothing {
    for l in (stage-failures $ran $stage (system-runner)) { fail $l }
}

# The config step of a root entry, into this run's failures and pending state.
def --env config-report [ran: record]: nothing -> nothing {
    if (entry-declined $ran (system-runner)) { system-declined "system layer" true; return }
    let code = stage-code $ran config
    if $code in [0 $EXIT_PENDING] { rm --force (pending-file) } else if $code != null { system-failed $ran config }
    if $code == $EXIT_PENDING { $env.DOT_SYSTEM_PENDING = true }
}

# What root's config stage needs from the user first: the unlocked secrets and the lfs objects.
def secrets-ready []: nothing -> nothing {
    if (profile-has secrets) { try { yubikey-unlock } catch {|e| fail (failure-line "dot secrets unlock" null (cause-text (cause-from-error $e))) } }
    if (which git-lfs | is-not-empty) {
        try { ^git -C $REPO ...$LFS_FILTER lfs pull } catch {|e| fail (failure-line "git lfs pull" null (cause-text (cause-from-error $e))) }
    }
}

export def --env apply-run [system: bool, user: bool, force: bool]: nothing -> table {
    failures-open
    secrets-ready
    if $system and (system-allowed) {
        $env.DOT_SYSTEM_RAN = true
        config-report (system-run config --force=$force)
    } else if $system and (admin) {
        system-skipped "system layer" true
    }
    if $user { link-run [] $force } else { [] }
}

export def user-locked []: nothing -> nothing {
    state-lock-hold run.lock "another dot run holds the user layer"
}

export def --env unlink-run [mod: string]: nothing -> table {
    let ctx = pipeline-load $REPO user
    let m = $ctx.modules | where id == $mod | get --optional 0
    if $m == null { error make {msg: $"no module ($mod); dot plan --modules lists them"} }
    if ($m.native | is-empty) { error make {msg: $"($mod) only declares packages, there is nothing to unlink"} }
    failures-open
    let rows = [link theme] | each {|verb|
        let prev = (state-read $mod $verb).outputs
        let seen = observe-outputs $prev user
        let actions = plan-module $mod [] $prev $seen (recorded-hashes) $REPO false
        {verb: $verb, prev: $prev, actions: $actions}
    }
    plan-print ($rows | each {|r| {id: $"($mod) ($r.verb)", native: true, error: null, actions: $r.actions} }) unlink
    let outcomes = $rows | each {|r|
        let done = apply-module $r.actions $m.dir user
        state-write $mod $r.verb "" $r.actions $done $r.prev
        $done
    } | flatten
    let kept = $rows | get actions | flatten | where kind == drift
    if ($kept | is-not-empty) { log-warn $"left in place, changed since the last apply: ($kept.target | str join ' ')" }
    [{id: $mod, ok: ($outcomes | all { $in.ok }), outcomes: $outcomes, ms: 0, log: "", error: null}]
}

# An incomplete run removes nothing but still records what it installed, so undeclaring it later counts as dropped.
def ledger-record [kind: string, declared: list<string>, installed: list<string>]: nothing -> nothing {
    ledger-set $kind (ledger-get $kind | append ($declared | where $it in $installed))
}

# What the kind's installed closure lists, null when its tool is absent or its query fails (failed, or warned
# --read-only; nothing removed).
def user-installed [kind: string, installed: closure, --read-only]: nothing -> any {
    if (which $kind | is-empty) { return null }
    try { do $installed } catch {|e|
        let message = $"($kind): listing installed packages: ($e.msg)"
        if $read_only { log-warn $message } else { fail $message }
        null
    }
}

# Flatpak apps and nix packages apply --packages offers to remove: recorded and no longer declared (dropped), installed
# by hand and in no keep list (by_hand).
export def user-packages-undeclared [declared: record, platform: record]: nothing -> record {
    let none = {dropped: [], by_hand: []}
    with-env {DOT_LAYER: user} {
        let flatpaks = user-installed flatpak { flatpak-installed } --read-only
        let nix = user-installed nix { nix-installed } --read-only
        {
            flatpak: (if $flatpaks == null { $none } else { ledger-diff (ledger-get flatpak) ($declared.flatpak | columns) $flatpaks $platform.flatpak_keep })
            nix: (if $nix == null { $none } else { ledger-diff (ledger-get nix) $declared.nix $nix $platform.nix_keep })
        }
    }
}

# What it could not install offline (online false): those downloads wait for the next apply --packages.
def install-user [declared: record, platform: record, yes: bool, offer_by_hand: bool, online: bool]: nothing -> list<string> {
    mut waiting = []
    if (which rustup | is-not-empty) {
        if $online {
            try { ^rustup default stable } catch { fail "rustup default stable" }
        } else if not (^rustup toolchain list | str contains "stable") {
            $waiting = $waiting | append "rustup stable"
        }
    }
    let complete = $declared.incomplete | is-empty
    if not $complete { fail $"ledger: not removing undeclared flatpak and nix packages, these modules declare none: ($declared.incomplete | str join ' ')" }
    let apps = $declared.flatpak | transpose app commit
    if (which flatpak | is-not-empty) {
        let exports = [($nu.home-dir | path join $FLATPAK_USER_EXPORTS) $FLATPAK_SYSTEM_EXPORTS]
        let dirs = $exports ++ ($env.XDG_DATA_DIRS? | default $DATA_DIRS_DEFAULT | split row ":") | uniq | str join ":"
        let deployed = {|app| ^flatpak info --user --show-commit $app | complete | if $in.exit_code == 0 { $in.stdout | str trim } else { "" } }
        let behind = with-env {XDG_DATA_DIRS: $dirs} { $apps | where {|a| (do $deployed $a.app) != $a.commit } | get app }
        if not $online and ($behind | is-not-empty) { $waiting = $waiting | append $"flatpak ($behind | str join ' ')" }
        with-env {XDG_DATA_DIRS: $dirs} {
            if ($apps | is-not-empty) and $online {
                if (^flatpak remote-add --user --if-not-exists flathub $FLATHUB | complete).exit_code != 0 {
                    fail "flatpak remote-add --user flathub"
                } else {
                    for a in $apps {
                        if not ($a.commit =~ '^[0-9a-f]{64}$') { fail $"flatpak ($a.app): no pinned commit"; continue }
                        let now = do $deployed $a.app
                        if $now != $a.commit {
                            if $a.app in (^flatpak mask --user | lines | str trim) { ^flatpak mask --user --remove $a.app }
                            if $now == "" and (try { ^flatpak install --user --noninteractive flathub $a.app; false } catch { true }) { fail $"flatpak install --user ($a.app)"; continue }
                            try { ^flatpak update --user --noninteractive $"--commit=($a.commit)" $a.app } catch { fail $"flatpak update --user --commit=($a.commit) ($a.app)" }
                        }
                        try { ^flatpak mask --user $a.app } catch { fail $"flatpak mask --user ($a.app)" }
                    }
                }
            }
            let installed = user-installed flatpak { flatpak-installed }
            if $installed != null {
                if not $complete { ledger-record flatpak ($declared.flatpak | columns) $installed } else {
                    ledger-remove flatpak ($declared.flatpak | columns) $installed $platform.flatpak_keep $yes --offer-by-hand=$offer_by_hand {|dropped|
                        let masked = ^flatpak mask --user | lines | str trim
                        $dropped | where $it in $masked | each { ^flatpak mask --user --remove $in } | ignore
                        ^flatpak uninstall --user --noninteractive ...$dropped
                        ^flatpak uninstall --user --noninteractive --unused
                    }
                }
            }
        }
    }
    let before = user-installed nix { nix-installed }
    if $before != null {
        let missing = $declared.nix | where $it not-in $before
        if ($missing | is-not-empty) and not $online { $waiting = $waiting | append $"nix ($missing | str join ' ')" }
        if ($missing | is-not-empty) and $online {
            try { ^nix ...$NIX_FLAGS profile add ...($missing | each { $"($NIXPKGS)#($in)" }) } catch { fail $"nix profile add ($missing | str join ' ')" }
        }
        let installed = if ($missing | is-empty) { $before } else { user-installed nix { nix-installed } }
        if $installed != null {
            if not $complete { ledger-record nix $declared.nix $installed } else {
                ledger-remove nix $declared.nix $installed $platform.nix_keep $yes --offer-by-hand=$offer_by_hand {|dropped|
                    ^nix ...$NIX_FLAGS profile remove ...$dropped
                }
            }
        }
    }
    $waiting
}

def --env install-begin []: nothing -> nothing {
    failures-begin ($env.DOT_RUN_FILE | str replace ".jsonl" ".install-failures")
}

# The install and packages steps of a root entry, into the install failures; the install step's code.
def --env install-report [ran: record]: nothing -> int {
    if (entry-declined $ran (system-runner)) { system-declined "packages" false; return $EXIT_PENDING }
    let install = stage-code $ran install
    if $install not-in [0 $EXIT_PENDING] { system-failed $ran install }
    if $install == $EXIT_PENDING { $env.DOT_SYSTEM_PENDING = true }
    if ($ran.stages | where stage == packages and code != 0 | is-not-empty) { system-failed $ran packages }
    $install
}

# Rustup, flatpak and nix as the user: after root's entry, so nothing slow sits between two of them.
def --env install-user-run [yes: bool, offer_by_hand: bool]: nothing -> nothing {
    let ctx = pipeline-load $REPO user
    let waiting = install-user (modules-packages $REPO $ctx.modules $ctx.platform) $ctx.platform $yes $offer_by_hand (network-online)
    if ($waiting | is-not-empty) {
        log-note $"packages pending, ($OFFLINE_PENDING) --packages: ($waiting | str join ', ')"
        $env.DOT_SYSTEM_PENDING = true
    }
}

# Ends the install failures into FAILURES.install: 0 when there are none, EXIT_ABORTED kept as it is.
def --env install-end [status: int = 0]: nothing -> int {
    let failed = failures-take
    let published = $REPO | path join $FAILURES_INSTALL
    if ($failed | is-empty) and $status != $EXIT_ABORTED { rm --force $published; return 0 }
    $"($failed)\n" | save --force $published
    if $status == $EXIT_ABORTED { return $EXIT_ABORTED }
    print $"=== FAILED ===\n($failed)"
    1
}

export def --env install-run [user: bool, yes: bool, offer_by_hand: bool]: nothing -> int {
    let system = not $user and (system-allowed)
    if not $user and not $system and (admin) { system-skipped "packages" false }
    install-begin
    if $system and (install-report (system-run install --yes=$yes)) == $EXIT_ABORTED { return (install-end $EXIT_ABORTED) }
    install-user-run $yes $offer_by_hand
    install-end
}

export def pending-file []: nothing -> path {
    state-dir | path join system-pending
}

export def --env system-part [target: string]: nothing -> nothing {
    let runner = if $env.DOT_SYSTEM? == "skip" { null } else { root-runner }
    let ok = $runner != null and (with-env {DOTFILES_ROOT_RUNNER: $runner} { system-run config }).code in [0 $EXIT_PENDING]
    if $ok { return }
    $"($target)\n" | save --append (pending-file)
    log-note $"($target): system part pending, runs on the next dot apply"
    $env.DOT_SYSTEM_PENDING = true
}

# Why root's last `apply` does not vouch for the system layer, null when its config step ended 0 and no step of it ended
# otherwise. report: SYSTEM_STAGES, null when there is none: `apply` removes it before it unpacks and writes it after
# its last step, so an entry cut short left none. Pending (EXIT_PENDING) is no 0.
export def stages-due [report: any]: nothing -> any {
    let stages = try { $report.stages | select stage code } catch { return "left no report, it did not finish" }
    let unsettled = $stages | where code != 0
    if ($unsettled | is-not-empty) { return $"ended ($unsettled | each { $'($in.stage) with ($in.code)' } | str join ', ')" }
    if "config" not-in $stages.stage { return $"ran no config step \(($stages.stage | str join ', ')\)" }
}

# What an unprivileged system plan (pipeline-plan's rows) shows root has to do, as "<module>: <kind> <target>": a
# module's error and every action but the ones that say nothing here. Those are a skip, a target this user cannot read,
# a step or exec with no record (it runs on every apply), and one whose --creates this user cannot look for.
export def plan-due [planned: table]: nothing -> list<string> {
    let errors = $planned | where error != null | each { $"($in.id): ($in.error)" }
    let actions = $planned | each {|m| $m.actions | each {|a|
        let d = $a.decl
        let silent = $a.kind in [skip unreadable] or ($a.kind in [exec step] and (
            not (action-recorded $d) or ($d.creates? != null and (dir-hidden ($d.creates | path dirname)))
        ))
        if not $silent { $"($m.id): ($a.kind) ($a.target)" }
    } } | flatten
    $errors ++ $actions
}

# Why a sync has to enter root, from what an unprivileged process can read; empty when all of it shows the system
# layer converged. checks: doctor's records. facts: per reason what was found of it, a reason when that is true, a text
# or a list that is not empty. Anything unknown is a reason.
export def system-due [checks: list<record>, facts: record]: nothing -> list<string> {
    let unsettled = $IDLE_CHECKS | each {|name|
        let rows = $checks | where check == $name
        if ($rows | is-empty) { $"($name): not checked" } else { $rows | where level != ok | get --optional 0 | if $in != null { $"($name): ($in.text)" } }
    } | compact
    $unsettled ++ ($facts | items {|reason, found|
        if $found == true { $reason } else if $found not-in [false null []] { $"($reason): (names-shown ([$found] | flatten) $DUE_SHOWN)" }
    } | compact)
}

# Why an upgrade pass is due by checkupdates' exit code, null when it found nothing to upgrade; no answer is a reason.
export def upgrades-due [exit_code: any]: nothing -> any {
    if $exit_code == $CHECKUPDATES_NONE { return null }
    if $exit_code == null { return "checkupdates is not installed" }
    if $exit_code == 0 { "package upgrades are available" } else { $"checkupdates exited ($exit_code), the mirrors' state is unknown" }
}

# A plain def: pipeline-load's DOT_LAYER stays in here.
def system-facts []: nothing -> record {
    let ctx = pipeline-load $REPO system
    let declared = modules-packages $REPO $ctx.modules $ctx.platform
    {
        "system part pending": (try { open --raw (with-env {DOT_LAYER: user} { pending-file }) | lines | where $it != "" } catch { [] })
        "migrations pending": (migrations-pending $REPO system | get id)
        "undeclared packages": (packages-convergence $declared.pacman $ctx.platform.packages_keep).remove
        "modules declaring no packages": $declared.incomplete
        "the system secrets differ from what root was last handed": ((file-trim $SYSTEM_SECRETS_DIGEST null) != (system-secrets-digest $REPO $ctx.platform.facts.wireguard?))
        "the config failure banner is up": ($CONFIG_ISSUE | path exists)
        "root's last entry": (stages-due (try { open $SYSTEM_STAGES } catch { null }))
        "the system plan": (plan-due (pipeline-plan $ctx system [] false))
    }
}

# system-due on this machine, then, only when nothing else is due, whether the mirrors hold an upgrade.
def system-due-now []: nothing -> list<string> {
    let due = try { system-due (doctor-checks) (system-facts) } catch {|e| [$"the system layer's state could not be read: ($e.msg)"] }
    if ($due | is-not-empty) { return $due }
    let code = if (which checkupdates | is-empty) { null } else { (^timeout $CHECKUPDATES_TIMEOUT_S checkupdates | complete).exit_code }
    [(upgrades-due $code)] | compact
}

# dot sync after its pull: migrations, one root entry for packages and the system layer, the user's packages, the user
# layer, the modules' update verbs. Root is left out when system-due-now finds nothing for it; system forces it.
export def --env update-run [yes: bool, system: bool]: nothing -> record {
    migrations-run $REPO user | ignore
    failures-open
    secrets-ready
    let config_failures = $env.FAILURES_FILE
    install-begin
    if (system-allowed) {
        let due = if $system { ["dot sync --system"] } else { system-due-now }
        if ($due | is-empty) {
            log-info "system layer: nothing to do, root not entered; dot sync --system enters it anyway"
        } else {
            log-debug $"system layer due: ($due | str join '; ')"
            $env.DOT_SYSTEM_RAN = true
            let ran = system-run sync --yes=$yes
            if (install-report $ran) == $EXIT_ABORTED { exit (install-end $EXIT_ABORTED) }
            # now, not after the user's installs: an interrupt in those must not lose a failed config step
            let installing = $env.FAILURES_FILE
            $env.FAILURES_FILE = $config_failures
            config-report $ran
            $env.FAILURES_FILE = $installing
        }
    } else if (admin) {
        system-skipped "packages" false
        system-skipped "system layer" true
    }
    install-user-run $yes false
    let install = install-end
    failures-open
    let results = link-run [] false
    try { ^nu --no-config-file $INTERNAL update } catch { log-warn "update: a module's update verb failed, see dot log" }
    {install: $install, results: $results}
}

export def managed-drift []: nothing -> table {
    let written = recorded-hashes
    let records = glob (state-dir | path join modules **/*.nuon) | each {|f|
        {id: ($f | path dirname | path relative-to (state-dir | path join modules)), outs: (try { open $f | get outputs } catch { [] })}
    }
    # one observation for every record: one stat, one readlink and one systemctl for the lot
    let every = $records | get outs | flatten
    let seen = observe-outputs $every user
    $records | each {|r|
        $r.outs | each {|o|
            let obs = $seen.paths | get --optional $o.target
            let state = match $o.kind {
                "file" => (output-file-state $o $obs $REPO ($written | get --optional $o.target))
                "link" => (if ($obs.type? | default "") == "" { "missing" } else if $obs.link != $o.source { "relinked" } else { null })
                "unit" => {
                    let now = $seen.units | get --optional $o.target
                    if (unit-state-holds ($o.state? | default enabled) $now) { null } else { $now | default missing }
                }
                _ => null
            }
            if $state == null { null } else { {module: $r.id, target: $o.target, drift: $state, pending: ($o.kind == "unit" or $state == "missing")} }
        } | compact
    } | flatten
}
