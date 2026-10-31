#!/usr/bin/nu --no-config-file
# Root's one entry: re-execs under one flock and interruptible.sh, only from the root-owned copy.

use log.nu *
use state.nu [SYSTEM_REPO SYSTEM_STATE EXIT_ABORTED EXIT_PENDING INSTALL_PASS_FILE]
use pipeline.nu [pipeline-load pipeline-plan pipeline-apply pending-save]
use modules.nu [modules-packages]
use ledger.nu [packages-convergence ledger-set ledger-packages ledger-units]
use preserve.nu [tty-confirm preserve-prune]
use migrate.nu [migrations-run]
use system.nu [system-unpack system-secrets ENTRY]
use cli.nu [supervise self-argv]
use sync.nu [bootstrap-const FINGERPRINT_VALUE]
use cause.nu [cause-from-output cause-text failure-line argv-text]

const EXIT_FAILURES = 1
const OFFLINE_WAIT_S = 120
# the mirror answers 429 past its per-ip budget: the wait grows 5s per try up to a minute, about 35 minutes in all
const DOWNLOAD_TRIES = 40
const OFFLINE_TRIES = 3
const DOWNLOAD_BACKOFF_STEP = 5sec
const DOWNLOAD_BACKOFF_MAX = 1min
const DOWNLOAD_ERRORS = '(?i)failed retrieving file|failed to retrieve some files|failed to synchronize|could not resolve|returned error: (403|429|5\d\d)|timed? ?out|too slow|connection (refused|reset)|could not connect|network is unreachable'
const LSCK0_DB = "/var/lib/pacman/sync/lsck0.db"
const PACMAN_LOCK = "/var/lib/pacman/db.lck"
const PACMAN_MODULE = "base/pacman"
const YUBIKEY_MODULE = "base/yubikey"
const ADDUSER_BIN = "/usr/local/bin/adduser-dotfiles"
const NOT_ON_MIRROR = "not on the mirror"

def repo-guard []: nothing -> path {
    let repo = $env.FILE_PWD | path dirname | path dirname
    if not (is-admin) { error make {msg: "run as root"} }
    if $repo != $SYSTEM_REPO or (^stat -c '%u %a' $repo | str trim) != "0 755" {
        error make {msg: $"runs only from a root-owned ($SYSTEM_REPO), not ($repo)"}
    }
    $repo
}

# Verbatim argv, always through /usr/bin/nu and the root copy.
def locked []: nothing -> nothing {
    let args = self-argv | skip until { $in | str ends-with $ENTRY } | skip 1
    supervise --lock ($SYSTEM_STATE | path join lock) --argv [/usr/bin/nu --no-config-file ($SYSTEM_REPO | path join $ENTRY) ...$args]
}

def --env failures-end [what: string]: nothing -> nothing {
    let failed = failures-take
    if ($failed | is-not-empty) {
        print -e $"=== system FAILED ===\n($failed)"
        exit $EXIT_FAILURES
    }
    log-info $"($what) done"
}

# --needed would still list installed ones; a group counts by its missing members.
def packages-wanted [names: list<string>]: nothing -> list<string> {
    let groups = ^pacman -Sgg | lines | parse "{group} {name}" | where group in $names
    let installed = ^pacman -Qq | lines
    let plain = $names | where $it not-in $groups.group
    let missing = if ($plain | is-empty) { [] } else { ^pacman -T ...$plain | complete | get stdout | lines }
    $missing ++ ($groups | where name not-in $installed | get name | uniq)
}

# Keeps pacman's stderr to tell a download error from the rest; stdout stays the tty for the bars.
def --wrapped pacman-try [...args: string]: nothing -> record {
    let err = mktemp --tmpdir
    let code = try { ^pacman ...$args e> $err; 0 } catch {|e| $e.exit_code? | default 1 }
    let text = open --raw $err
    rm --force $err
    if ($text | is-not-empty) { print -e --no-newline $text }
    let ok = $code == 0
    {ok: $ok, code: $code, text: $text, download: (not $ok and $text =~ $DOWNLOAD_ERRORS), refused: (not $ok and $text =~ 'returned error: (403|429)')}
}

# The FAILURES line of a pacman run that failed: the command, its exit code and its last stderr lines.
export def pacman-failure [what: string, args: list<string>, code: int, stderr: string, --tries: int]: nothing -> string {
    let cause = cause-text (cause-from-output (argv-text [pacman ...$args]) $code $stderr)
    let text = if $tries == null { $cause } else { $"download failed ($tries) times, the last: ($cause)" }
    failure-line pacman $what $text
}

# EXIT_ABORTED when a download never got through, EXIT_FAILURES on any other error.
def --wrapped pacman-retry [what: string, tries: int, ...args: string]: nothing -> nothing {
    mut try = 1
    loop {
        let r = pacman-try ...$args
        if $r.ok { return }
        if not $r.download { fail (pacman-failure $what $args $r.code $r.text); exit $EXIT_FAILURES }
        if $try >= $tries { fail (pacman-failure $what $args $r.code $r.text --tries $tries); exit $EXIT_ABORTED }
        let wait = [($DOWNLOAD_BACKOFF_STEP * $try) $DOWNLOAD_BACKOFF_MAX] | math min
        let why = if $r.refused { "the mirror refused it (403/429), likely a rate ban, so waiting it out" } else { "the network or a mirror dropped" }
        log-warn $"($what): download failed, ($why), try ($try)/($tries), again in ($wait)"
        sleep $wait
        $try += 1
    }
}

# pacman -Sp's complaints over stdout and stderr: targets no repo has, and dependencies none satisfies with who needs
# them (pacman prints the latter to stdout).
export def sync-errors-parse [output: list<string>]: nothing -> record {
    {
        not_found: ($output | parse "error: target not found: {name}" | get name | uniq)
        unsatisfied: ($output | parse --regex "unable to satisfy dependency '(?<dep>[^']+)' required by (?<by>\\S+)" | uniq)
    }
}

# The targets whose dependency closure does not resolve, found by halving: a half that resolves is cleared whole.
export def packages-culprits [targets: list<string>, probe: closure]: nothing -> list<string> {
    if ($targets | is-empty) or (do $probe $targets).ok { return [] }
    if ($targets | length) == 1 { return $targets }
    let half = ($targets | length) // 2
    (packages-culprits ($targets | first $half) $probe) ++ (packages-culprits ($targets | skip $half) $probe)
}

# Drops targets until probe (pacman -Sp: {ok, output}) resolves the rest: the ones not found first, then the ones a
# missing dependency names, then, for one only a dependency of theirs needs, the targets pulling it in. Stops when a
# round finds nothing to drop, so an error of another kind is left to the install pass.
export def packages-resolve [targets: list<string>, probe: closure]: nothing -> record {
    mut kept = $targets
    mut dropped = []
    while ($kept | is-not-empty) {
        let current = $kept
        let r = do $probe $current
        if $r.ok { break }
        let found = sync-errors-parse $r.output
        let direct = $found.unsatisfied | where by in $current
        let gone = if ($found.not_found | is-not-empty) {
            $found.not_found | each {|n| {name: $n, why: $NOT_ON_MIRROR} }
        } else if ($direct | is-not-empty) {
            $direct | each {|d| {name: $d.by, why: $"needs ($d.dep), which no repo has"} }
        } else if ($found.unsatisfied | is-not-empty) {
            let deps = $found.unsatisfied | each { $"($in.dep) \(for ($in.by)\)" } | str join ", "
            packages-culprits $current $probe | each {|n| {name: $n, why: $"pulls in ($deps), which no repo has"} }
        } else { [] }
        let gone = $gone | where name in $current | uniq-by name
        if ($gone | is-empty) { break }
        $dropped = $dropped ++ $gone
        $kept = $current | where $it not-in $gone.name
    }
    {kept: $kept, dropped: $dropped}
}

# --packages-unchecked: runs even before the module's packages are installed (base/pacman, ahead of the install pass).
def module-system [ctx: record, id: string, --packages-unchecked]: nothing -> bool {
    let planned = pipeline-plan $ctx system [$id] false --packages-unchecked=$packages_unchecked
    let results = pipeline-apply $ctx $planned system 1
    pending-save $planned.id $results
    $results | all { $in.ok }
}

def main [] {
    error make {msg: $"system-apply.nu <apply|install|config|packages|module|migrate|preserve-prune>"}
}

# apply <sha> <install|config>: unpack the repo and secrets archive on stdin, run the stage from the new copy
def "main apply" [sha: string, stage: string, --unattended, --force, --yes]: nothing -> nothing {
    repo-guard | ignore
    if $stage not-in [install config] { error make {msg: $"apply: ($stage) is neither install nor config"} }
    locked
    let work = mktemp --directory --tmpdir-path /run
    let status = try {
        ^tar -x --no-same-owner --no-same-permissions -C $work -f - repo.tar secrets.tar
        open --raw ($work | path join repo.tar) | system-unpack $SYSTEM_REPO $sha
        let entry = $SYSTEM_REPO | path join $ENTRY
        let flags = if $stage == "install" { [--unattended=($unattended) --yes=($yes)] } else { [--unattended=($unattended) --force=($force)] }
        try { open --raw ($work | path join secrets.tar) | ^/usr/bin/nu --no-config-file $entry $stage ...$flags; 0 } catch {|e| $e.exit_code? | default 1 }
    } catch {|e|
        rm --recursive --force $work
        error make {msg: $e.msg}
    }
    rm --recursive --force $work
    exit $status
}

def --env unattended [on: bool]: nothing -> nothing {
    if $on { $env.DOTFILES_UNATTENDED = "1" }
}

# every declared package from [lsck0] in one pass, base/pacman first, base/yubikey last
def "main install" [--unattended, --yes]: nothing -> nothing {
    let repo = repo-guard
    locked
    unattended $unattended
    failures-begin ($SYSTEM_STATE | path join FAILURES)
    # the install stage runs base/pacman's verb, so root's state is migrated before it, as config does
    migrations-run $repo system | ignore
    ^pacman-key --init
    ^pacman-key --populate archlinux
    let offline = (which nm-online | is-not-empty) and not (try { ^nm-online $"--timeout=($OFFLINE_WAIT_S)"; true } catch { false })
    if $offline { log-warn $"still offline after ($OFFLINE_WAIT_S)s" }
    let ctx = pipeline-load $repo system
    # pipeline-apply records the failure itself
    if not (module-system $ctx $PACMAN_MODULE --packages-unchecked) { exit $EXIT_ABORTED }
    # a power cut mid-transaction leaves the lock, and every retry boot would fail on it
    if ($PACMAN_LOCK | path exists) and (^pgrep -x pacman | complete).exit_code != 0 { rm --force $PACMAN_LOCK }
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    pacman-retry "the database sync" (if $offline { $OFFLINE_TRIES } else { $DOWNLOAD_TRIES }) -Syy --noconfirm
    # one package the mirror cannot resolve drops only itself and what needs it, never the whole pass
    let probe = {|targets|
        let r = with-env {LC_ALL: C} { ^pacman -Sp --noconfirm --print-format "%n" ...$targets | complete }
        {ok: ($r.exit_code == 0), output: ($r.stdout + $r.stderr | lines)}
    }
    let resolved = packages-resolve $declared.pacman $probe
    for d in $resolved.dropped {
        if $d.why == $NOT_ON_MIRROR {
            fail $"($NOT_ON_MIRROR): ($d.name) \(a name new since the last nightly build arrives with the next one\)"
        } else {
            fail $"($d.name): ($d.why), left out of this pass; what needs it stays pending"
        }
    }
    let available = $resolved.kept
    let wanted = packages-wanted $available
    log-info $"sources: ($available | length) packages, ($wanted | length) to install in one pass, ($resolved.dropped | length) left out"
    # -uu moves pacstrap's packages onto the snapshot and a pin back onto an older one; --ask 4 replaces old names
    let upgrade = if $unattended or ($ctx.platform.facts.lsck0_snapshot | is-not-empty) { "-Suu" } else { "-Su" }
    pacman-retry "the install pass" $DOWNLOAD_TRIES $upgrade --needed --noconfirm --ask 4 ...$wanted
    date now | format date '%+' | save --force $INSTALL_PASS_FILE
    let snapshot = $"($ctx.platform.facts.lsck0_snapshot | default latest) (ls $LSCK0_DB | get 0.modified | date to-timezone UTC | format date '%FT%TZ') (open --raw $LSCK0_DB | hash sha256)"
    ledger-set snapshot [$snapshot]
    if ($declared.incomplete | is-not-empty) {
        fail $"ledger: not removing dropped packages, these modules declare none: ($declared.incomplete | str join ' ')"
    } else {
        try { ledger-packages $declared.pacman $yes } catch {|e| fail $"ledger: removing dropped packages: ($e.msg)" }
    }
    if ($declared.nix | is-not-empty) and (which nix | is-not-empty) {
        try { ^systemctl enable --now nix-daemon.socket } catch { fail "nix-daemon.socket" }
        # nix ships no /nix/store and a user's first call fails on it
        if not ("/nix/store" | path exists) { ^install -d -o root -g nixbld -m 1775 /nix/store }
    }
    module-system $ctx $YUBIKEY_MODULE | ignore
    failures-end install
}

# every system verb; the secrets arrive as a tar on stdin into a tmpfs gone at exit
def "main config" [--unattended, --force]: nothing -> nothing {
    let repo = repo-guard
    locked
    unattended $unattended
    failures-begin ($SYSTEM_STATE | path join FAILURES)
    # a pending migration converts root's state before any verb reads it, also without a sync
    migrations-run $repo system | ignore
    let ctx = pipeline-load $repo system
    let secrets = mktemp --directory --tmpdir-path /run
    let waiting = try {
        ^tar -x --no-same-owner --no-same-permissions -C $secrets -f -
        let allowed = system-secrets $ctx.platform.facts.wireguard?
        ^find $secrets -mindepth 1 ! -type d -print0 | split row (char nul) | where $it != ""
        | where {|f| ($f | path type) != "file" or ($f | path relative-to $secrets) not-in $allowed } | each { rm --force $in } | ignore
        $env.DOTFILES_SECRETS = $secrets
        let planned = pipeline-plan $ctx system [] $force | where id != $PACMAN_MODULE
        let results = pipeline-apply $ctx $planned system 1
        pending-save $planned.id $results --full
        $results | any { $in.pending? != null }
    } catch {|e|
        rm --recursive --force $secrets
        error make {msg: $e.msg}
    }
    rm --recursive --force $secrets
    rm --force $ADDUSER_BIN
    $"#!/bin/sh\n[ \"$\(id -u\)\" = 0 ] || exec sudo \"$0\" \"$@\"\nexec /usr/bin/nu --no-config-file ($SYSTEM_REPO | path join $ENTRY) adduser \"$@\"\n" | save $ADDUSER_BIN
    ^chmod 755 $ADDUSER_BIN
    try { ledger-units $repo ($ctx.modules | where cfg.enable | get dir) system | ignore } catch {|e| fail $"ledger: disabling dropped units: ($e.msg)" }
    # last, so every initramfs and cmdline change of this run is rebuilt once, then signed and verified
    try { ^/usr/bin/nu --no-config-file -I ($repo | path join scripts lib) -c $"use ($repo | path join configs base boot boot.nu) [boot-commit]; boot-commit" } catch { fail "boot barrier (configs/base/boot/boot.nu boot-commit)" }
    failures-end config
    if $waiting { exit $EXIT_PENDING }
}

# remove explicit packages no module declares, after a yes
def "main packages" [--yes, --plan, --unattended]: nothing -> nothing {
    let repo = repo-guard
    unattended $unattended
    locked
    let ctx = pipeline-load $repo system
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    if ($declared.incomplete | is-not-empty) {
        error make {msg: $"not removing anything, these modules declare no packages right now: ($declared.incomplete | str join ' ')"}
    }
    let found = packages-convergence $declared.pacman $ctx.platform.packages_keep
    if ($found.remove | is-empty) { return }
    print $"not declared by any module: ($found.remove | str join ' ')"
    if $plan or not ($yes or (tty-confirm $"remove these ($found.remove | length)?")) { return }
    ^pacman -D --asdeps ...$found.remove | ignore
    let orphans = ^pacman -Qdttq | complete | get stdout | lines | where $it in $found.remove
    let kept = $found.remove | where $it not-in $orphans
    if ($kept | is-not-empty) { log-info $"still needed by another package, kept as a dependency: ($kept | str join ' ')" }
    if ($orphans | is-empty) { return }
    ^pacman -Rns --noconfirm ...$orphans
}

# module <id>: that module's system verb alone, for running it by hand; the system verb is the only one root runs
def "main module" [id: string]: nothing -> nothing {
    let repo = repo-guard
    locked
    let ctx = pipeline-load $repo system
    if "system" not-in ($ctx.modules | where id == $id | get --optional 0.native | default []) { error make {msg: $"($id) has no native system verb"} }
    if not (module-system $ctx $id) { exit 1 }
}

def "main migrate" [--baseline]: nothing -> nothing {
    let repo = repo-guard
    locked
    migrations-run $repo system --baseline=$baseline | ignore
}

def "main preserve-prune" [days: int]: nothing -> nothing {
    repo-guard | ignore
    locked
    preserve-prune $days
}

const USERNAME_PATTERN = '^[a-z_][a-z0-9_-]{0,31}$'
const PROFILE_CUSTOM = "custom"

# adduser-dotfiles <name> [--profile <p>]: a non-wheel login with its own checkout; rerun-safe.
def "main adduser" [name: string, --profile: string]: nothing -> nothing {
    let repo = repo-guard
    if not ($name =~ $USERNAME_PATTERN) { error make {msg: $"invalid name '($name)', expected ($USERNAME_PATTERN)"} }
    let profiles = glob ($repo | path join profiles *.nuon) | each { path parse | get stem } | sort | append $PROFILE_CUSTOM
    let picked = if $profile != null { $profile } else if (is-terminal --stdin) {
        print -e $"profiles: ($profiles | str join ' ')"
        input $"profile for ($name) [($PROFILE_CUSTOM)]: " | default --empty $PROFILE_CUSTOM
    } else { $PROFILE_CUSTOM }
    if $picked not-in $profiles { error make {msg: $"unknown profile '($picked)', one of: ($profiles | str join ' ')"} }
    let existing = ^id -u $name | complete
    if $existing.exit_code == 0 and ($existing.stdout | str trim | into int) < 1000 {
        error make {msg: $"($name) is a system account, not a login to add"}
    }
    if $existing.exit_code != 0 { ^useradd -m -s /usr/bin/zsh $name }
    if (^passwd -S $name | split row " " | get 1) != "P" { ^passwd $name }
    let home = ^getent passwd $name | split row ":" | get 5
    let checkout = $home | path join projects arch-dotfiles
    if not ($checkout | path join .git | path exists) {
        let dotfiles_url = bootstrap-const $repo DOTFILES_URL
        let key_file = bootstrap-const $repo SIGNING_KEY_FILE
        let fingerprint = bootstrap-const $repo SIGNING_KEY_FINGERPRINT $FINGERPRINT_VALUE
        ^runuser -u $name -- git clone $dotfiles_url $checkout
        let gnupg = ^runuser -u $name -- mktemp -d | str trim
        ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" gpg --batch --quiet --import ($repo | path join $key_file)
        let status = ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" git -C $checkout verify-commit --raw HEAD | complete
        rm --recursive --force $gnupg
        if $status.exit_code != 0 or not ($status.stderr | str contains "VALIDSIG") or ($status.stderr | lines | where ($it | str contains VALIDSIG) | first | split row " " | last) != $fingerprint {
            rm --recursive --force $checkout
            error make {msg: $"($dotfiles_url) HEAD is not signed by ($fingerprint), refusing it"}
        }
    }
    let live = $home | path join .config dotfiles profile.nuon
    if $picked != $PROFILE_CUSTOM and not ($live | path exists) {
        ^runuser -u $name -- install -Dm644 ($checkout | path join profiles $"($picked).nuon") $live
    }
    # root's copy: the login can write its own checkout
    let picked_file = $repo | path join profiles $"($picked).nuon"
    if $picked != $PROFILE_CUSTOM and ("secrets" in (open $picked_file | get --optional capabilities | default [])) {
        let owners = "/var/lib/dotfiles/owners"
        let have = if ($owners | path exists) { open --raw $owners | lines } else { [] }
        if $name not-in $have { $"($name)\n" | save --append $owners }
    }
    ^systemd-run --quiet --wait --pipe --collect $"--uid=($name)" -p PAMName=login -p $"WorkingDirectory=($checkout)" nu --no-config-file scripts/dot.nu apply --packages --user
}
