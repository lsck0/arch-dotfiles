# The runs behind dot's commands, the system layer through root included.

const REPO = path self ../..
use log.nu *
use cli.nu [concat jobs supervise]
use state.nu [SYSTEM_REPO SYSTEM_STATE state-dir EXIT_ABORTED EXIT_PENDING xdg]
use platform.nu [platform-load]
use profile.nu [profile-has]
use modules.nu [modules-packages]
use pipeline.nu [pipeline-load pipeline-plan pipeline-apply pending-save flatpak-installed nix-installed THEME_VERB_TIMEOUT NIX_FLAGS]
use converge.nu [state-read observe plan-module recorded-hashes apply-module state-write output-file-state]
use ledger.nu [ledger-units ledger-get ledger-set ledger-diff ledger-remove]
use migrate.nu [migrations-run]
use ../../configs/base/yubikey/yubikey.nu [yubikey-unlock]
use system.nu [system-pack system-archive ENTRY]
use ../../configs/core/wallust/wallpaper.nu [wallpaper-set]
use sync.nu [sync-pull]
use cause.nu [cause-from-error cause-text failure-line failure-is-system SYSTEM_FIX]
use online.nu [network-online OFFLINE_PENDING]

export const INTERNAL = path self internal.nu
const FAILURES = "FAILURES.config"
const FAILURES_INSTALL = "FAILURES.install"
const NIXPKGS = "github:NixOS/nixpkgs/b6c8664de9b6cc07fe5666a29f91884ba81197c4"
const FLATHUB = "https://dl.flathub.org/repo/flathub.flatpakrepo"
const LFS_FILTER = [
    -c "filter.lfs.clean=git-lfs clean -- %f" -c "filter.lfs.smudge=git-lfs smudge -- %f"
    -c "filter.lfs.process=git-lfs filter-process" -c filter.lfs.required=true
]
const FLATPAK_SYSTEM_EXPORTS = "/var/lib/flatpak/exports/share"
const FLATPAK_USER_EXPORTS = ".local/share/flatpak/exports/share"
const DATA_DIRS_DEFAULT = "/usr/local/share:/usr/share"
const SYSTEM_SEED = 'set -e; umask 022; copy=$1; mkdir -p "${copy%/*}"; exec 9>"${copy%/*}/lock"; flock 9; rm -rf "$copy.new"; mkdir -m 700 "$copy.new"; tar -x --no-same-owner --no-same-permissions -C "$copy.new" -f -; printf "%s\n" "$2" > "$copy.new/.source"; [ ! -d "$copy.new/configs/secrets" ] || chmod -R go= "$copy.new/configs/secrets"; chmod 755 "$copy.new"; rm -rf "$copy"; mv "$copy.new" "$copy"'
const THEME_STAMP_PATHS = [configs/core/wallust themes 'configs/*/*/mod.nu']
const THEME_DEFAULT_WALLPAPER = "alena-aenami-cover-art-007-3.jpg"

def summary [results: table]: nothing -> nothing {
    let outcomes = $results | get outcomes | concat
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
    $env.GOPATH = $nu.home-dir | path join .local share go
    pipeline-plan $ctx link $mods $force
}

export def --env link-run [mods: list<string>, force: bool]: nothing -> table {
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
    let ids = $planned | where native and id not-in ($ctx.modules | where broken | get id) and id not-in $waiting | get id
    # an empty id list means every module to pipeline-plan: a run that planned no link rows themes none
    let themed = if ($wallpaper | path exists) and ($ids | is-not-empty) {
        let real_wallpaper = ^readlink -f $wallpaper | str trim
        pipeline-plan $ctx theme $ids false [$real_wallpaper] | where native
        | pipeline-apply $ctx $in theme (jobs) [$real_wallpaper] --timeout $THEME_VERB_TIMEOUT
    } else { [] }
    if $full {
        for dir in [$nu.home-dir ($nu.home-dir | path join .local bin)] {
            ls -a $dir | where type == symlink | where {|l| not ($l.name | path exists) and ((^readlink $l.name) | str starts-with $"($REPO)/") } | each { rm $in.name } | ignore
        }
        let units = ledger-units $REPO ($ctx.modules | where cfg.enable | get dir) user
        $units.by_hand | each { log-info $"enabled by hand, not managed: ($in)" } | ignore
        theme-init
    }
    summary ($results ++ $themed)
    $results ++ $themed
}

def theme-init []: nothing -> nothing {
    let files = ^git -C $REPO ls-files --cached --others --exclude-standard ...$THEME_STAMP_PATHS | lines | where $it != ""
        | each {|f| $REPO | path join $f } | where ($it | path exists) | uniq
    let stamp = ^sha1sum ...$files | ^sha1sum | str trim
    let cache = xdg cache wal
    let current = try { open --raw ($cache | path join .theme-stamp) | str trim } catch { "" }
    if ($cache | path join wallpaper | path exists) and $current == $stamp {
        return
    }
    let link = $cache | path join wallpaper
    let wallpaper = if ($link | path exists) { ^readlink -f $link | str trim } else { $THEME_DEFAULT_WALLPAPER }
    wallpaper-set $wallpaper --sync
    $"($stamp)\n" | save --force ($cache | path join .theme-stamp)
}

def --env failures-open []: nothing -> nothing {
    if ($env.FAILURES_FILE? | is-empty) {
        $env.FAILURES_FILE = $env.DOT_RUN_FILE | str replace ".jsonl" ".failures"
        $env.DOT_FAILURES_OWNED = true
    }
}

export def failures-publish [results: table]: nothing -> bool {
    let owned = $env.DOT_FAILURES_OWNED? == true
    let failures = if $owned and ($env.FAILURES_FILE | path exists) { open --raw $env.FAILURES_FILE | str trim } else { "" }
    if ($failures | is-not-empty) {
        let published = $REPO | path join $FAILURES
        # a partial run adds to what earlier runs recorded instead of replacing it
        let earlier = if ($published | path exists) { open --raw $published | lines } else { [] }
        let kept = if ($env.DOT_FULL_RUN? != true) { $earlier } else if ($env.DOT_SYSTEM_RAN? != true) {
            $earlier | where {|l| failure-is-system $l }
        } else { [] }
        let failures = $kept | append ($failures | lines) | where ($it | str trim) != "" | uniq | str join "\n"
        $"($failures)\n" | save --force $"($published).($env.DOT_RUN_ID)"
        mv --force $"($published).($env.DOT_RUN_ID)" $published
        print "=== FAILED ==="
        print $failures
        return false
    }
    if ($results | any { not $in.ok }) { return false }
    # a user-only run cannot vouch for the system layer: its earlier failures stay published until it runs again
    let published = $REPO | path join $FAILURES
    let system_stale = $env.DOT_SYSTEM_RAN? != true and ($published | path exists) and (open --raw $published | lines | any {|l| failure-is-system $l })
    if $owned and ($env.DOT_FULL_RUN? == true) and not $system_stale { rm --force $published }
    true
}

export def finish [results: table]: nothing -> nothing {
    run-journal
    if not (failures-publish $results) { exit 1 }
}

export def admin []: nothing -> bool {
    ^id -nG | split row " " | any { $in == wheel }
}

export def system-allowed []: nothing -> bool {
    $env.DOT_SYSTEM? != "skip" and (admin)
}

export def --env pty-log [name: string, args: list<string>]: nothing -> nothing {
    if ($env.DOT_PTY_LOG? | is-not-empty) { return }
    if not (is-terminal --stdin) { $env.DOTFILES_UNATTENDED = "1" }
    if (is-terminal --stdout) and (which script | is-not-empty) {
        let cmd = [nu --no-config-file ($REPO | path join scripts dot.nu) ...$args] | each {|w| $"'($w | str replace --all "'" "'\\''")'" } | str join " "
        exec env DOT_PTY_LOG=1 script -qe -c $cmd ($REPO | path join $"($name).log")
    }
}

def system-run [stage: string, --force, --yes]: nothing -> int {
    let runner = $env.DOTFILES_ROOT_RUNNER? | default sudo
    let head = ^git -C $REPO rev-parse HEAD | str trim
    let entry = $SYSTEM_REPO | path join $ENTRY
    if not ($entry | path exists) {
        if $runner != "sudo" { error make {msg: $"($SYSTEM_REPO) has no ($ENTRY) yet, run dot apply at a terminal once"} }
        system-pack $REPO | ^sudo sh -c $SYSTEM_SEED sh $SYSTEM_REPO $head
    }
    let forced = if $force { [--force] } else { [] }
    let asked = if $yes { [--yes] } else { [] }
    let flags = [--unattended=($env.DOTFILES_UNATTENDED? == "1")] ++ $forced ++ $asked
    let archive = system-archive $REPO (platform-load $REPO).facts.wireguard?
    let code = try { $archive | ^$runner $entry apply $head $stage ...$flags; 0 } catch {|e| $e.exit_code? | default 1 }
    interrupted-exit $code
    $code
}

# sudo's pty can take the interrupt alone; the exit code (130, or -2) carries it.
def interrupted-exit [code: int]: nothing -> nothing {
    if $code in [130 -2] {
        log-err "interrupted (ctrl+c) in the system layer: the run stopped, its later phases did not run"
        exit 130
    }
}

export def --env system-skipped [what: string, pending: bool]: nothing -> nothing {
    if $pending { $"($what)\n" | save --append (pending-file) }
    log-note $"system part pending \(DOT_SYSTEM=skip\): ($what)"
    $env.DOT_SYSTEM_PENDING = true
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

# Root's own lines carry the causes; this run's, by their time. A root line naming no system module gets the layer as
# its subject, so a later user-only run still knows it for root's. Without one, the layer's exit is the line.
def system-failed [stage: string, code: int, since: datetime]: nothing -> nothing {
    let root = $SYSTEM_STATE | path join FAILURES
    let fresh = ($root | path exists) and (ls $root | get 0.modified) >= $since
    let lines = if $fresh { open --raw $root | lines | where ($it | str trim) != "" } else { [] }
    for l in $lines { fail (if (failure-is-system $l) { $l } else { $"system layer ($l)" }) }
    if ($lines | is-empty) {
        let runner = $env.DOTFILES_ROOT_RUNNER? | default sudo
        let fix = $"($SYSTEM_FIX) at a terminal; root's run log: ($SYSTEM_STATE | path join runs)"
        fail (failure-line $"system layer ($stage)" null $"($runner) ($ENTRY) exited ($code), root recorded no failure" --fix $fix)
    }
}

export def --env apply-run [system: bool, user: bool, force: bool]: nothing -> table {
    failures-open
    if (profile-has secrets) { try { yubikey-unlock } catch {|e| fail (failure-line "dot secrets unlock" null (cause-text (cause-from-error $e))) } }
    if (which git-lfs | is-not-empty) {
        try { ^git -C $REPO ...$LFS_FILTER lfs pull } catch {|e| fail (failure-line "git lfs pull" null (cause-text (cause-from-error $e))) }
    }
    if $system and (system-allowed) {
        $env.DOT_SYSTEM_RAN = true
        let since = date now
        let code = system-run config --force=$force
        if $code in [0 $EXIT_PENDING] { rm --force (pending-file) } else { system-failed config $code $since }
        if $code == $EXIT_PENDING { $env.DOT_SYSTEM_PENDING = true }
    } else if $system and (admin) {
        system-skipped "system layer" true
    }
    if $user { link-run [] $force } else { [] }
}

export def user-locked []: nothing -> nothing {
    let lock = state-dir | path join run.lock
    if ($env.DOT_LOCK? | default "") != $lock and ($lock | path exists) and (^flock --nonblock $lock true | complete).exit_code != 0 {
        print -e "dot: another dot run holds the user layer, waiting for it"
    }
    supervise --lock $lock
}

export def --env unlink-run [mod: string]: nothing -> table {
    let ctx = pipeline-load $REPO user
    let m = $ctx.modules | where id == $mod | get --optional 0
    if $m == null { error make {msg: $"no module ($mod); dot plan --modules lists them"} }
    if ($m.native | is-empty) { error make {msg: $"($mod) only declares packages, there is nothing to unlink"} }
    failures-open
    let rows = [link theme] | each {|verb|
        let prev = (state-read $mod $verb).outputs
        let seen = observe ($prev | where kind != unit | get target) ($prev | where kind == unit | get target) user
        let actions = plan-module $mod [] $prev $seen (recorded-hashes) $REPO false
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

export def --env install-run [user: bool, yes: bool, offer_by_hand: bool]: nothing -> int {
    let system = not $user and (system-allowed)
    if not $user and not $system and (admin) { system-skipped "packages" false }
    failures-begin ($env.DOT_RUN_FILE | str replace ".jsonl" ".install-failures")
    if $system {
        let since = date now
        let status = system-run install --yes=$yes
        if $status != 0 { system-failed install $status $since }
        if $status == $EXIT_ABORTED {
            $"(failures-take)\n" | save --force ($REPO | path join $FAILURES_INSTALL)
            return $EXIT_ABORTED
        }
    }
    let ctx = pipeline-load $REPO user
    let waiting = install-user (modules-packages $REPO $ctx.modules $ctx.platform) $ctx.platform $yes $offer_by_hand (network-online)
    if ($waiting | is-not-empty) {
        log-note $"packages pending, ($OFFLINE_PENDING) --packages: ($waiting | str join ', ')"
        $env.DOT_SYSTEM_PENDING = true
    }
    if $system {
        try { ^sudo ($SYSTEM_REPO | path join $ENTRY) packages --unattended=($env.DOTFILES_UNATTENDED? == "1") ...(if $yes { [--yes] } else { [] }) } catch {|e| interrupted-exit ($e.exit_code? | default 1); fail "system layer: removing undeclared packages" }
    }
    let failed = failures-take
    if ($failed | is-empty) { rm --force ($REPO | path join $FAILURES_INSTALL); return 0 }
    $"($failed)\n" | save --force ($REPO | path join $FAILURES_INSTALL)
    print $"=== FAILED ===\n($failed)"
    1
}

export def pending-file []: nothing -> path {
    state-dir | path join system-pending
}

export def --env system-part [target: string]: nothing -> nothing {
    let tty = is-terminal --stdin
    let graphical = ($env.WAYLAND_DISPLAY? | is-not-empty) or ($env.DISPLAY? | is-not-empty)
    let runner = if $env.DOT_SYSTEM? == "skip" { null } else if $tty { "sudo" } else if $graphical and (which pkexec | is-not-empty) { "pkexec" } else { null }
    let ok = $runner != null and (with-env {DOTFILES_ROOT_RUNNER: $runner} { system-run config }) in [0 $EXIT_PENDING]
    if $ok { return }
    $"($target)\n" | save --append (pending-file)
    log-note $"($target): system part pending, runs on the next dot apply"
    $env.DOT_SYSTEM_PENDING = true
}

export def --env update-run [yes: bool]: nothing -> record {
    sync-pull $REPO
    migrations-run $REPO user | ignore
    let install = install-run false $yes false
    if $install == $EXIT_ABORTED { exit $EXIT_ABORTED }
    if (system-allowed) {
        try { ^sudo ($SYSTEM_REPO | path join $ENTRY) migrate } catch {|e| interrupted-exit ($e.exit_code? | default 1); fail "system layer: migrations" }
    } else if (admin) { system-skipped "system migrations" false }
    let results = apply-run true true false
    try { ^nu --no-config-file $INTERNAL update } catch { log-warn "update: a module's update verb failed, see dot log" }
    {install: $install, results: $results}
}

export def managed-drift []: nothing -> table {
    let written = recorded-hashes
    let records = glob (state-dir | path join modules **/*.nuon) | each {|f|
        {id: ($f | path dirname | path relative-to (state-dir | path join modules)), outs: (open $f | get outputs)}
    }
    # one observation for every record: one stat, one readlink and one systemctl for the lot
    let every = $records | get outs | flatten
    let seen = observe ($every | where kind != unit | get --optional target | default []) ($every | where kind == unit | get --optional target | default []) user
    $records | each {|r|
        let id = $r.id
        $r.outs | each {|o|
            let obs = $seen.paths | get --optional $o.target
            let state = match $o.kind {
                "file" => (output-file-state $o $obs $REPO ($written | get --optional $o.target))
                "link" => (if ($obs.type? | default "") == "" { "missing" } else if $obs.link != $o.source { "relinked" } else { null })
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
