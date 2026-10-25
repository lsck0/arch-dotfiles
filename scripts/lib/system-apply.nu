#!/usr/bin/nu --no-config-file
# Root's one entry, what sudo or the polkit action runs: each command re-execs itself under one flock and
# interruptible.sh (sudo relays ctrl+c, which nushell's try would swallow) and runs only from the root-owned copy.

use log.nu *
use state.nu [SYSTEM_REPO SYSTEM_STATE state-dir]
use pipeline.nu [pipeline-load pipeline-plan pipeline-apply]
use modules.nu [modules-packages]
use ledger.nu [packages-convergence ledger-get ledger-set ledger-packages ledger-units]
use preserve.nu [tty-confirm preserve-prune]
use migrate.nu [migrations-run]
use system.nu [system-unpack system-secrets ENTRY]

const EXIT_FAILURES = 1
const EXIT_ABORTED = 2
const OFFLINE_WAIT_S = 120
# the mirror answers 429 past its per-ip budget; each pass after the budget refills fetches the next files.
# The wait grows linearly (5s, 10s, ... up to a minute): a client hammering a refusing mirror every 5s only
# deepens the refusal. 40 tries wait about 35 minutes in all.
const DOWNLOAD_TRIES = 40
const OFFLINE_TRIES = 3
const DOWNLOAD_BACKOFF_STEP = 5sec
const DOWNLOAD_BACKOFF_MAX = 1min
const DOWNLOAD_ERRORS = '(?i)failed retrieving file|failed to retrieve some files|failed to synchronize|could not resolve|returned error: (403|429|5\d\d)|timed? ?out|too slow|connection (refused|reset)|could not connect|network is unreachable'
const LSCK0_DB = "/var/lib/pacman/sync/lsck0.db"
const PACMAN_LOCK = "/var/lib/pacman/db.lck"
const PACMAN_MODULE = "base/pacman"
const YUBIKEY_MODULE = "base/yubikey"
const ADDUSER_LINK = "/usr/local/bin/adduser-dotfiles"

def repo-guard []: nothing -> path {
    let repo = $env.FILE_PWD | path dirname | path dirname
    if not (is-admin) { error make {msg: "run as root"} }
    if $repo != $SYSTEM_REPO or (^stat -c '%u %a' $repo | str trim) != "0 755" {
        error make {msg: $"runs only from a root-owned ($SYSTEM_REPO), not ($repo)"}
    }
    $repo
}

# Re-execs this very command line (the arguments after this script's path, verbatim) once under the lock.
def locked []: nothing -> nothing {
    if ($env.DOT_SYSTEM_LOCKED? | is-empty) {
        mkdir $SYSTEM_STATE
        let argv = open --raw $"/proc/($nu.pid)/cmdline" | into binary | decode utf-8 | split row (char nul) | drop 1
        let args = $argv | skip until { $in | str ends-with $ENTRY } | skip 1
        exec ($SYSTEM_REPO | path join scripts lib interruptible.sh) --lock ($SYSTEM_STATE | path join lock) env DOT_SYSTEM_LOCKED=1 /usr/bin/nu --no-config-file ($SYSTEM_REPO | path join $ENTRY) ...$args
    }
}

def --env failures-start []: nothing -> nothing {
    $env.FAILURES_FILE = $SYSTEM_STATE | path join FAILURES
    "" | save --force $env.FAILURES_FILE
}

def failures-end [what: string]: nothing -> nothing {
    let failed = open --raw $env.FAILURES_FILE | str trim
    if ($failed | is-not-empty) {
        print -e $"=== system FAILED ===\n($failed)"
        exit $EXIT_FAILURES
    }
    log-info $"($what) done"
}

# The targets still missing; --needed would still name every installed one, and a group counts by its
# missing members.
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
    let ok = try { ^pacman ...$args e> $err; true } catch { false }
    let text = open --raw $err
    rm --force $err
    if ($text | is-not-empty) { print -e --no-newline $text }
    {ok: $ok, download: (not $ok and $text =~ $DOWNLOAD_ERRORS), refused: (not $ok and $text =~ 'returned error: (403|429)')}
}

# Retries a download error up to tries times; exits EXIT_ABORTED when it never got through, EXIT_FAILURES
# on any other error.
def --wrapped pacman-retry [what: string, tries: int, ...args: string]: nothing -> nothing {
    mut try = 1
    loop {
        let r = pacman-try ...$args
        if $r.ok { return }
        if not $r.download { fail $"pacman: ($what) failed"; exit $EXIT_FAILURES }
        if $try >= $tries { fail $"pacman: ($what): download failed ($tries) times"; exit $EXIT_ABORTED }
        let wait = [($DOWNLOAD_BACKOFF_STEP * $try) $DOWNLOAD_BACKOFF_MAX] | math min
        let why = if $r.refused { "the mirror refused it (403/429), likely a rate ban, so waiting it out" } else { "the network or a mirror dropped" }
        log-warn $"($what): download failed, ($why), try ($try)/($tries), again in ($wait)"
        sleep $wait
        $try += 1
    }
}

def module-system [ctx: record, id: string]: nothing -> bool {
    pipeline-apply $ctx (pipeline-plan $ctx system [$id] false) system 1 | all { $in.ok }
}

def main [] {
    error make {msg: $"system-apply.nu <apply|install|config|packages|module|migrate|preserve-prune>"}
}

# apply <sha> <install|config>: unpack the repo and secrets archive on stdin, run the stage from the new copy
def "main apply" [sha: string, stage: string, --unattended, --force]: nothing -> nothing {
    repo-guard | ignore
    if $stage not-in [install config] { error make {msg: $"apply: ($stage) is neither install nor config"} }
    locked
    let work = mktemp --directory --tmpdir-path /run
    let status = try {
        ^tar -x --no-same-owner --no-same-permissions -C $work -f - repo.tar secrets.tar
        open --raw ($work | path join repo.tar) | system-unpack $SYSTEM_REPO $sha
        let entry = $SYSTEM_REPO | path join $ENTRY
        let flags = if $stage == "install" { [--unattended=($unattended)] } else { [--unattended=($unattended) --force=($force)] }
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
def "main install" [--unattended]: nothing -> nothing {
    let repo = repo-guard
    locked
    unattended $unattended
    failures-start
    ^pacman-key --init
    ^pacman-key --populate archlinux
    let offline = (which nm-online | is-not-empty) and not (try { ^nm-online $"--timeout=($OFFLINE_WAIT_S)"; true } catch { false })
    if $offline { log-warn $"still offline after ($OFFLINE_WAIT_S)s" }
    let ctx = pipeline-load $repo system
    if not (module-system $ctx $PACMAN_MODULE) {
        fail $PACMAN_MODULE
        exit $EXIT_ABORTED
    }
    # a power cut mid-transaction leaves the lock, and every retry boot would fail on it
    if ($PACMAN_LOCK | path exists) and (^pgrep -x pacman | complete).exit_code != 0 { rm --force $PACMAN_LOCK }
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    pacman-retry "the database sync" (if $offline { $OFFLINE_TRIES } else { $DOWNLOAD_TRIES }) -Syy --noconfirm
    let missing = ^pacman -Sp --noconfirm --print-format "%n" ...$declared.pacman | complete | get stderr | lines | parse "error: target not found: {p}" | get p
    $missing | each { fail $"not on the mirror: ($in) \(a name new since the last nightly build arrives with the next one\)" } | ignore
    let available = $declared.pacman | where $it not-in $missing
    let wanted = packages-wanted $available
    log-info $"sources: ($available | length) packages, ($wanted | length) to install in one pass, ($missing | length) not on the mirror"
    # -uu moves pacstrap's packages onto the snapshot and a pin back onto an older one; --ask 4 replaces old names
    let upgrade = if $unattended or ($ctx.platform.facts.lsck0_snapshot | is-not-empty) { "-Suu" } else { "-Su" }
    pacman-retry "the install pass" $DOWNLOAD_TRIES $upgrade --needed --noconfirm --ask 4 ...$wanted
    let snapshot = $"($ctx.platform.facts.lsck0_snapshot | default latest) (ls $LSCK0_DB | get 0.modified | date to-timezone UTC | format date '%FT%TZ') (open --raw $LSCK0_DB | hash sha256)"
    ledger-set snapshot [$snapshot]
    try { ledger-packages $declared.pacman } catch {|e| fail $"ledger: removing dropped packages: ($e.msg)" }
    if ($declared.nix | is-not-empty) and (which nix | is-not-empty) {
        try { ^systemctl enable --now nix-daemon.socket } catch { fail "nix-daemon.socket" }
        # nix ships no /nix/store and a user's first call fails on it
        if not ("/nix/store" | path exists) { ^install -d -o root -g nixbld -m 1775 /nix/store }
    }
    if not (module-system $ctx $YUBIKEY_MODULE) { fail $YUBIKEY_MODULE }
    failures-end install
}

# every system verb; the secrets arrive as a tar on stdin into a tmpfs gone at exit
def "main config" [--unattended, --force]: nothing -> nothing {
    let repo = repo-guard
    locked
    unattended $unattended
    failures-start
    # a pending migration converts root's state before any verb reads it, also without a sync
    migrations-run $repo system | ignore
    let ctx = pipeline-load $repo system
    let secrets = mktemp --directory --tmpdir-path /run
    try {
        ^tar -x --no-same-owner --no-same-permissions -C $secrets -f -
        let allowed = system-secrets $ctx.platform.facts.wireguard?
        ^find $secrets -mindepth 1 ! -type d -print0 | split row (char nul) | where $it != ""
        | where {|f| ($f | path type) != "file" or ($f | path relative-to $secrets) not-in $allowed } | each { rm --force $in } | ignore
        $env.DOTFILES_SECRETS = $secrets
        let planned = pipeline-plan $ctx system [] $force | where id != $PACMAN_MODULE
        pipeline-apply $ctx $planned system 1 | ignore
    } catch {|e|
        rm --recursive --force $secrets
        error make {msg: $e.msg}
    }
    rm --recursive --force $secrets
    ls /usr/local/bin | where type == symlink | where { (^readlink $in.name | str starts-with "/home/") } | each { rm $in.name } | ignore
    rm --force $ADDUSER_LINK
    $"#!/bin/sh\n[ \"$\(id -u\)\" = 0 ] || exec sudo \"$0\" \"$@\"\nexec /usr/bin/nu --no-config-file ($SYSTEM_REPO | path join $ENTRY) adduser \"$@\"\n" | save $ADDUSER_LINK
    ^chmod 755 $ADDUSER_LINK
    try { ledger-units $repo ($ctx.modules | where cfg.enable | get dir) system | ignore } catch {|e| fail $"ledger: disabling dropped units: ($e.msg)" }
    # last, so every initramfs and cmdline change of this run is rebuilt once, then signed and verified
    try { ^/usr/bin/nu --no-config-file -I ($repo | path join scripts lib) -c $"use ($repo | path join configs base boot boot.nu) [boot-commit]; boot-commit" } catch { fail "boot barrier (configs/base/boot/boot.nu boot-commit)" }
    failures-end config
}

# remove explicit packages no module declares, keep list aside, recorded in the ledger for rollback
def "main packages" [--yes, --plan, --unattended]: nothing -> nothing {
    let repo = repo-guard
    unattended $unattended
    locked
    let ctx = pipeline-load $repo system
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    let found = packages-convergence $declared.pacman $ctx.platform.packages_keep
    if ($found.remove | is-empty) { return }
    print $"not declared by any module: ($found.remove | str join ' ')"
    if $plan or not ($yes or (tty-confirm $"remove these ($found.remove | length)?")) { return }
    ^pacman -D --asdeps ...$found.remove | ignore
    let orphans = ^pacman -Qdttq | complete | get stdout | lines | where $it in $found.remove
    let kept = $found.remove | where $it not-in $orphans
    if ($kept | is-not-empty) { log-info $"still needed by another package, kept as a dependency: ($kept | str join ' ')" }
    if ($orphans | is-empty) { return }
    let versions = ^pacman -Q ...$orphans | lines
    ^pacman -Rns --noconfirm ...$orphans
    ledger-set removed (ledger-get removed | append ($versions | each {|v| $"($v) (date now | format date '%F')" }))
}

def "main module" [id: string, verb: string]: nothing -> nothing {
    let repo = repo-guard
    locked
    let ctx = pipeline-load $repo system
    if $verb not-in ($ctx.modules | where id == $id | get --optional 0.native | default []) { error make {msg: $"($id) has no native ($verb) verb"} }
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
const SIGNING_KEY_FINGERPRINT = "E7501F533316E9AFC6AAE907122F2CB527D1EFE3"
const SIGNING_KEY_FILE = "configs/core/gnupg/luca-sandrock.pub.asc"
const DOTFILES_URL = "https://github.com/lsck0/arch-dotfiles.git"
const PROFILE_CUSTOM = "custom"

# adduser-dotfiles <name> [--profile <p>]: a new non-wheel login with its own verified checkout and user layer;
# rerun-safe. The profile is a profiles/ name or custom (nothing personal); without the flag it is asked on a tty
def "main adduser" [name: string, --profile: string]: nothing -> nothing {
    let repo = repo-guard
    if not ($name =~ $USERNAME_PATTERN) { error make {msg: $"invalid name '($name)', expected ($USERNAME_PATTERN)"} }
    let profiles = glob ($repo | path join profiles *.nuon) | each { path parse | get stem } | sort | append $PROFILE_CUSTOM
    let picked = if $profile != null { $profile } else if (^test -t 0 | complete).exit_code == 0 {
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
        ^runuser -u $name -- git clone $DOTFILES_URL $checkout
        let gnupg = ^runuser -u $name -- mktemp -d | str trim
        ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" gpg --batch --quiet --import ($SYSTEM_REPO | path join $SIGNING_KEY_FILE)
        let status = ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" git -C $checkout verify-commit --raw HEAD | complete
        rm --recursive --force $gnupg
        if $status.exit_code != 0 or not ($status.stderr | str contains $"VALIDSIG") or ($status.stderr | lines | where ($it | str contains VALIDSIG) | first | split row " " | last) != $SIGNING_KEY_FINGERPRINT {
            rm --recursive --force $checkout
            error make {msg: $"($DOTFILES_URL) HEAD is not signed by ($SIGNING_KEY_FINGERPRINT), refusing it"}
        }
    }
    let live = $home | path join .config dotfiles profile.nuon
    if $picked != $PROFILE_CUSTOM and not ($live | path exists) {
        ^runuser -u $name -- install -Dm644 ($checkout | path join profiles $"($picked).nuon") $live
    }
    let picked_file = $checkout | path join profiles $"($picked).nuon"
    if $picked != $PROFILE_CUSTOM and ("secrets" in (open $picked_file | get --optional capabilities | default [])) {
        let owners = "/var/lib/dotfiles/owners"
        let have = if ($owners | path exists) { open --raw $owners | lines } else { [] }
        if $name not-in $have { $"($name)\n" | save --append $owners }
    }
    ^systemd-run --quiet --wait --pipe --collect $"--uid=($name)" -p PAMName=login -p $"WorkingDirectory=($checkout)" nu --no-config-file scripts/dot.nu apply --packages --user
    ^systemd-run --quiet --wait --pipe --collect $"--uid=($name)" -p PAMName=login -p $"WorkingDirectory=($checkout)" nu --no-config-file scripts/dot.nu apply --user
}
