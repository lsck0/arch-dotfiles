#!/usr/bin/nu --no-config-file
# root's one entry, run only from the root-owned copy; apply is the single command sudo or polkit allows

use log.nu *
use state.nu [SYSTEM_REPO SYSTEM_STATE]
use pipeline.nu [pipeline-load pipeline-plan pipeline-apply]
use modules.nu [modules-packages]
use ledger.nu [packages-convergence ledger-get ledger-set ledger-packages ledger-generation ledger-units]
use written.nu [tty-confirm written-begin written-prune written-end preserve-prune]
use migrate.nu [migrations-run]
use system.nu [system-unpack system-secrets ENTRY]

# dot stage retries an abort, moves on from a run that only recorded failures
const EXIT_FAILURES = 1
const EXIT_ABORTED = 2
const OFFLINE_WAIT_S = 120
# the mirror answers 429 past its per-ip budget; each pass after the budget refills fetches the next files
const DOWNLOAD_TRIES = 80
const DOWNLOAD_BACKOFF = 5sec
const LSCK0_DB = "/var/lib/pacman/sync/lsck0.db"
const PACMAN_LOCK = "/var/lib/pacman/db.lck"
const PACMAN_MODULE = "base/pacman"
const YUBIKEY_MODULE = "base/yubikey"
const ADDUSER_LINK = "/usr/local/bin/adduser-dotfiles"
const PRE_APPLY_KEEP = 5
const PRE_APPLY_COMMENT = "dot pre-apply"

def repo-guard []: nothing -> path {
    let repo = $env.FILE_PWD | path dirname | path dirname
    if not (is-admin) { error make {msg: "run as root"} }
    if $repo != $SYSTEM_REPO or (^stat -c '%u %a' $repo | str trim) != "0 755" {
        error make {msg: $"runs only from a root-owned ($SYSTEM_REPO), not ($repo)"}
    }
    $repo
}

# one system run at a time: re-exec the whole command under flock
def --wrapped locked [...args: string]: nothing -> nothing {
    if ($env.DOT_SYSTEM_LOCKED? | is-empty) {
        mkdir $SYSTEM_STATE
        exec flock ($SYSTEM_STATE | path join lock) env DOT_SYSTEM_LOCKED=1 /usr/bin/nu --no-config-file ($SYSTEM_REPO | path join $ENTRY) ...$args
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

# --needed still names every installed target "up to date -- skipping"; a group by its missing members
def packages-wanted [names: list<string>]: nothing -> list<string> {
    let groups = ^pacman -Sgg | lines | parse "{group} {name}" | where group in $names
    let installed = ^pacman -Qq | lines
    let plain = $names | where $it not-in $groups.group
    let missing = if ($plain | is-empty) { [] } else { ^pacman -T ...$plain | complete | get stdout | lines }
    $missing ++ ($groups | where name not-in $installed | get name | uniq)
}

def module-system [ctx: record, id: string]: nothing -> bool {
    pipeline-apply $ctx (pipeline-plan $ctx system [$id] false) system 1 | all { $in.ok }
}

def main [] {
    error make {msg: $"system-apply.nu <apply|install|config|snapshot|packages|module|migrate|preserve-prune>"}
}

# apply <sha> <install|config>: unpack the repo and secrets archive on stdin, run the stage from the new copy
def "main apply" [sha: string, stage: string, --snapshot, --unattended, --force, --pin: string]: nothing -> nothing {
    repo-guard | ignore
    if $stage not-in [install config] { error make {msg: $"apply: ($stage) is neither install nor config"} }
    let flags = [--unattended=($unattended)] ++ (if $pin == null { [] } else { [--pin $pin] })
    locked apply $sha $stage --snapshot=($snapshot) ...$flags
    let work = mktemp --directory --tmpdir-path /run
    ^tar -x --no-same-owner --no-same-permissions -C $work -f - repo.tar secrets.tar
    open --raw ($work | path join repo.tar) | system-unpack $SYSTEM_REPO $sha
    let entry = $SYSTEM_REPO | path join $ENTRY
    if $snapshot { ^/usr/bin/nu --no-config-file $entry snapshot }
    let flags = if $stage == "install" { $flags } else { [--unattended=($unattended)] ++ (if $force { [--force] } else { [] }) }
    let status = try { open --raw ($work | path join secrets.tar) | ^/usr/bin/nu --no-config-file $entry $stage ...$flags; 0 } catch {|e| $e.exit_code? | default 1 }
    rm --recursive --force $work
    exit $status
}

def --env unattended [on: bool]: nothing -> nothing {
    if $on { $env.DOTFILES_UNATTENDED = "1" }
}

# every declared package from [lsck0] in one pass, base/pacman first, base/yubikey last
def "main install" [--unattended, --pin: string]: nothing -> nothing {
    let repo = repo-guard
    locked install --unattended=($unattended) ...(if $pin == null { [] } else { [--pin $pin] })
    unattended $unattended
    failures-start
    ^pacman-key --init
    ^pacman-key --populate archlinux
    if (which nm-online | is-not-empty) and not (try { ^nm-online $"--timeout=($OFFLINE_WAIT_S)"; true } catch { false }) { log-warn $"still offline after ($OFFLINE_WAIT_S)s" }
    let ctx = pipeline-load $repo system | if $pin == null { $in } else { update platform.facts.lsck0_snapshot $pin }
    if not (module-system $ctx $PACMAN_MODULE) {
        fail $PACMAN_MODULE
        exit $EXIT_ABORTED
    }
    # a power cut mid-transaction leaves the lock, and every retry boot would fail on it
    if ($PACMAN_LOCK | path exists) and (^pgrep -x pacman | complete).exit_code != 0 { rm --force $PACMAN_LOCK }
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    ^pacman -Syy --noconfirm
    # nothing is built here: what the mirror lacks is reported
    let missing = ^pacman -Sp --noconfirm --print-format "%n" ...$declared.pacman | complete | get stderr | lines | parse "error: target not found: {p}" | get p
    $missing | each { fail $"not on the mirror: ($in)" } | ignore
    let available = $declared.pacman | where $it not-in $missing
    let wanted = packages-wanted $available
    log-info $"sources: ($available | length) packages, ($wanted | length) to install in one pass, ($missing | length) not on the mirror"
    # -uu moves pacstrap's packages onto the snapshot, --ask 4 replaces the old lsck0-* names
    mut try = 1
    while not (try { ^pacman -Suu --needed --noconfirm --ask 4 ...$wanted; true } catch { false }) {
        if $try >= $DOWNLOAD_TRIES { fail "pacman: the install pass failed"; exit $EXIT_ABORTED }
        log-warn $"transaction failed, try ($try)/($DOWNLOAD_TRIES), again in ($DOWNLOAD_BACKOFF)"
        sleep $DOWNLOAD_BACKOFF
        $try += 1
    }
    let snapshot = $"($ctx.platform.facts.lsck0_snapshot | default latest) (ls $LSCK0_DB | get 0.modified | date to-timezone UTC | format date '%FT%TZ') (open --raw $LSCK0_DB | hash sha256)"
    ledger-set snapshot [$snapshot]
    let source = $repo | path join .source
    if ($source | path exists) { ledger-generation ($SYSTEM_STATE | path join generations) (open --raw $source | str trim) $snapshot }
    # after the pass, so a dropped package only leaves once whatever replaced it is in
    try { ledger-packages $declared.pacman } catch {|e| fail $"ledger: removing dropped packages: ($e.msg)" }
    if ($declared.nix | is-not-empty) and (which nix | is-not-empty) {
        try { ^systemctl enable --now nix-daemon.socket } catch { fail "nix-daemon.socket" }
        # nix ships no /nix/store and a user's first call fails on it; the owner and mode nix gives it itself
        if not ("/nix/store" | path exists) { ^install -d -o root -g nixbld -m 1775 /nix/store }
    }
    # card access before the first config: its secrets unlock runs as the user ahead of the system layer
    if not (module-system $ctx $YUBIKEY_MODULE) { fail $YUBIKEY_MODULE }
    failures-end install
}

# every system verb; the secrets arrive as a tar on stdin into a tmpfs gone at exit
def "main config" [--unattended, --force]: nothing -> nothing {
    let repo = repo-guard
    locked config --unattended=($unattended)
    unattended $unattended
    failures-start
    let ctx = pipeline-load $repo system
    let secrets = mktemp --directory --tmpdir-path /run
    ^tar -x --no-same-owner --no-same-permissions -C $secrets -f -
    let allowed = system-secrets $ctx.platform.facts.wireguard?
    ^find $secrets -mindepth 1 ! -type d -print0 | split row (char nul) | where $it != ""
    | where {|f| ($f | path type) != "file" or ($f | path relative-to $secrets) not-in $allowed } | each { rm --force $in } | ignore
    $env.DOTFILES_SECRETS = $secrets
    written-begin
    let planned = pipeline-plan $ctx system [] $force | where id != $PACMAN_MODULE
    # one at a time: the system modules share pacman, /etc/group and the boot queue
    let results = pipeline-apply $ctx $planned system 1
    if ($results | all { $in.ok }) { written-prune [] } else { written-end }
    rm --recursive --force $secrets
    # root runs nothing from a home
    ls /usr/local/bin | where type == symlink | where { (^readlink $in.name | str starts-with "/home/") } | each { rm $in.name } | ignore
    rm --force $ADDUSER_LINK
    $"#!/bin/sh\n[ \"$\(id -u\)\" = 0 ] || exec sudo \"$0\" \"$@\"\nexec /usr/bin/nu --no-config-file ($SYSTEM_REPO | path join $ENTRY) adduser \"$@\"\n" | save $ADDUSER_LINK
    ^chmod 755 $ADDUSER_LINK
    try { ledger-units $repo $ctx.platform.groups system | ignore } catch {|e| fail $"ledger: disabling dropped units: ($e.msg)" }
    # last, so every initramfs and cmdline change of this run is rebuilt once, then signed and verified
    try { ^/usr/bin/nu --no-config-file -I ($repo | path join scripts lib) -c $"use ($repo | path join configs base boot boot.nu) [boot-commit]; boot-commit" } catch { fail "boot barrier (configs/base/boot/boot.nu boot-commit)" }
    failures-end config
}

def snapshots []: nothing -> table {
    ^timeshift --list --scripted | lines
    | parse --regex '^\s*\d+\s+>\s+(?<name>\S+)\s+(?<tags>\S+)\s+(?<comment>.*)$'
    | where ($it.comment | str starts-with $PRE_APPLY_COMMENT) | sort-by name
}

# a timeshift snapshot before the system changes
def "main snapshot" []: nothing -> nothing {
    let repo = repo-guard
    locked snapshot
    let fstype = ^findmnt -n -o FSTYPE / | str trim
    if (^systemd-detect-virt | complete | get stdout | str trim) == "wsl" or $fstype != "btrfs" {
        log-info $"no pre-apply snapshot: / is ($fstype), not btrfs"
        return
    }
    # the first install pass is the one that brings timeshift
    if (which timeshift | is-empty) { return }
    let sha = open --raw ($repo | path join .source) | str trim | str substring 0..11
    # timeshift narrates every step and tries a desktop notification, which root has no session for
    let made = ^timeshift --create --scripted --tags O --comments $"($PRE_APPLY_COMMENT) ($sha)" | complete
    if $made.exit_code != 0 { error make {msg: $"timeshift --create: ($made.stdout)($made.stderr)"} }
    log-info $"pre-apply snapshot of ($sha)"
    for old in (snapshots | drop $PRE_APPLY_KEEP | get name) { ^timeshift --delete --scripted --snapshot $old | complete | ignore }
}

# remove explicit packages no module declares, keep list aside, recorded in the ledger for rollback
def "main packages" [--yes, --plan]: nothing -> nothing {
    let repo = repo-guard
    locked packages --yes=($yes) --plan=($plan)
    let ctx = pipeline-load $repo system
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    let found = packages-convergence $declared.pacman $ctx.platform.packages_keep
    if ($found.remove | is-empty) { return }
    print $"not declared by any module: ($found.remove | str join ' ')"
    if $plan or not ($yes or (tty-confirm $"remove these ($found.remove | length)?")) { return }
    let versions = ^pacman -Q ...$found.remove | lines
    ^pacman -Rns --noconfirm ...$found.remove
    ledger-set removed (ledger-get removed | append ($versions | each {|v| $"($v) (date now | format date '%F')" }))
}

def "main module" [id: string, verb: string]: nothing -> nothing {
    let repo = repo-guard
    locked module $id $verb
    let ctx = pipeline-load $repo system
    if $verb not-in ($ctx.modules | where id == $id | get --optional 0.native | default []) { error make {msg: $"($id) has no native ($verb) verb"} }
    if not (module-system $ctx $id) { exit 1 }
}

def "main migrate" [--baseline]: nothing -> nothing {
    let repo = repo-guard
    locked migrate --baseline=($baseline)
    migrations-run $repo system --baseline=$baseline | ignore
}

def "main preserve-prune" [days: int]: nothing -> nothing {
    repo-guard | ignore
    locked preserve-prune ($days | into string)
    preserve-prune $days
}

const USERNAME_PATTERN = '^[a-z_][a-z0-9_-]{0,31}$'
const SIGNING_KEY_FINGERPRINT = "E7501F533316E9AFC6AAE907122F2CB527D1EFE3"
const SIGNING_KEY_FILE = "configs/core/gnupg/luca-sandrock.pub.asc"
const DOTFILES_URL = "https://github.com/lsck0/arch-dotfiles.git"

# adduser-dotfiles <name>: a new non-wheel login with its own verified checkout and user layer; rerun-safe
def "main adduser" [name: string]: nothing -> nothing {
    repo-guard | ignore
    if not ($name =~ $USERNAME_PATTERN) { error make {msg: $"invalid name '($name)', expected ($USERNAME_PATTERN)"} }
    if (^id -u $name | complete).exit_code != 0 { ^useradd -m -s /usr/bin/zsh $name }
    # a rerun after a skipped passwd asks again
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
    let template = $checkout | path join profiles $"($name).nuon"
    let profile = $home | path join .config dotfiles profile.nuon
    if ($template | path exists) and not ($profile | path exists) { ^runuser -u $name -- install -Dm644 $template $profile }
    # a login session, so user units and the bus work like after a real login
    ^systemd-run --quiet --wait --pipe --collect $"--uid=($name)" -p PAMName=login -p $"WorkingDirectory=($checkout)" nu --no-config-file scripts/dot.nu install --user
    ^systemd-run --quiet --wait --pipe --collect $"--uid=($name)" -p PAMName=login -p $"WorkingDirectory=($checkout)" nu --no-config-file scripts/dot.nu link
}
