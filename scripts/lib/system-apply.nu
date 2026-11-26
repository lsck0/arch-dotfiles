#!/usr/bin/nu --no-config-file
# Root's one entry: re-execs under one flock and interruptible.sh, only from the root-owned copy.

use log.nu *
use state.nu [SYSTEM_REPO SYSTEM_STATE NU_ROOT EXIT_ABORTED EXIT_PENDING INSTALL_PASS_FILE CONFIG_ISSUE process-running tmp-dir-run group-exists save-atomic file-lines]
use pipeline.nu [module-get pipeline-load pipeline-plan pipeline-apply pending-save barriers-run]
use options.nu [ROOT_OPTIONS_DIR OPTION_ENABLE options-schema option-value-errors options-nuon-set enable-raised]
use platform.nu [PLATFORM_TARGET platform-load platform-spec platform-errors platform-value-errors]
use modules.nu [modules-packages]
use ledger.nu [packages-convergence packages-orphans-remove ledger-get ledger-set ledger-packages ledger-units awaited-names LEDGER_AWAITED LSCK0_DB]
use preserve.nu [tty-confirm preserve-prune]
use migrate.nu [migrations-run]
use system.nu [system-unpack system-secrets secrets-digest bootstrap-const ENTRY FINGERPRINT_VALUE SYSTEM_STAGES SYSTEM_SECRETS_DIGEST RUN_ID]
use cli.nu [supervise self-argv]
use cause.nu [cause-from-output cause-text failure-line argv-text]
use profile.nu [profile-owner-add]
use ../../platforms/homelab.nu [HOMELAB]
use homelab.nu [LSCK0_SECTION]

const EXIT_FAILURES = 1
const OFFLINE_WAIT_S = 120
# the mirror answers 429 past its per-ip budget: the wait grows 5s per try up to a minute, about 35 minutes in all
const DOWNLOAD_TRIES = 40
const OFFLINE_TRIES = 3
const DOWNLOAD_BACKOFF_STEP = 5sec
const DOWNLOAD_BACKOFF_MAX = 1min
const DOWNLOAD_ERRORS = '(?i)failed retrieving file|failed to retrieve some files|failed to synchronize|could not resolve|returned error: (403|429|5\d\d)|timed? ?out|too slow|connection (refused|reset)|could not connect|network is unreachable'
const PACMAN_LOCK = "/var/lib/pacman/db.lck"
const PACMAN_CONF = "/etc/pacman.conf"
const ADDUSER_BIN = "/usr/local/bin/adduser-dotfiles"
const NOT_ON_MIRROR = "not on the mirror"
const MIRROR_PROBE_TIMEOUT_S = 5
# curl's %{http_code} when no http answer came at all
const HTTP_NO_ANSWER = "000"
const ADMIN_GROUP = "wheel"
# what one root entry runs for `apply <sha> <stage>`, in order, each from the unpacked copy
const STAGES = {install: [install packages], config: [config], sync: [install packages config]}
const PACKAGES_FAILED = "removing undeclared packages"
# what a step of a root entry failed with, read back by stages-run
const FAILURES = $SYSTEM_STATE | path join FAILURES
# a tmpfs: the handed secrets never reach a disk
const RUN_TMP = "/run"

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
    supervise --lock ($SYSTEM_STATE | path join lock) --argv [$NU_ROOT --no-config-file ($SYSTEM_REPO | path join $ENTRY) ...$args]
}

# Root's run file, one per root entry: a stage `apply` starts inherits it, and only one inside root's own runs dir, so
# no environment handed to root names the file it appends to.
def --env run-open [name: string]: nothing -> nothing {
    let inherited = $env.DOT_RUN_FILE? | default ""
    let id = $env.DOT_RUN_ID? | default ""
    if $id =~ $RUN_ID and $inherited == (runs-dir | path join $"($id).jsonl") and ($inherited | path exists) { return }
    run-begin $name
}

# What every locked entry starts with: the guard, the lock, --unattended and the run file named name; the root copy.
def --env entry-begin [name: string, unattended: bool = false]: nothing -> path {
    let repo = repo-guard
    locked
    if $unattended { $env.DOTFILES_UNATTENDED = "1" }
    run-open $name
    $repo
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

# Whether the lab's mirror gave no http answer at all; a 403 or 429 is an answer, which pacman-retry waits out.
def mirror-silent []: nothing -> bool {
    let db = ($HOMELAB.mirror.lsck0 | str replace '$arch' x86_64) + "/lsck0.db"
    let probe = ^curl -s -m $MIRROR_PROBE_TIMEOUT_S -r 0-0 -o /dev/null -w "%{http_code}" $db | complete
    ($probe.stdout | str trim) == $HTTP_NO_ANSWER
}

# The names [lsck0] lacks, by whether its build could know them yet. recorded: "name first-asked" lines; a name is
# awaited while the mirror's database (built) is older than its first ask, and failed once a build after it still lacks
# it (a typo, a build that broke). record: the lines to keep.
export def mirror-awaited [names: list<string>, recorded: list<string>, built: any, now: datetime]: nothing -> record {
    let known = $recorded | parse "{name} {asked}"
    let record = $names | each {|n| $"($n) ($known | where name == $n | get --optional 0.asked | default ($now | format date '%+'))" }
    let awaited = awaited-names $record $built
    {awaited: $awaited, failed: ($names | where $it not-in $awaited), record: $record}
}

# What `apply` exits with for its stages' codes: an aborted install first, then a failure, then pending.
export def stages-exit [codes: list<int>]: nothing -> int {
    if $EXIT_ABORTED in $codes { return $EXIT_ABORTED }
    if ($codes | any { $in not-in [0 $EXIT_PENDING] }) { return $EXIT_FAILURES }
    if $EXIT_PENDING in $codes { $EXIT_PENDING } else { 0 }
}

# Runs stage's steps from the unpacked copy, each a process of its own under the lock this one holds; an aborted
# install ends them. secrets: the tar the config step reads.
def stages-run [stage: string, secrets: path, unattended: bool, force: bool, yes: bool]: nothing -> table {
    let entry = $SYSTEM_REPO | path join $ENTRY
    mut rows = []
    for step in ($STAGES | get $stage) {
        if ($rows | any { $in.code == $EXIT_ABORTED }) { break }
        "" | save --force $FAILURES
        let flags = [--unattended=($unattended)] ++ (if $step == "config" { [--force=($force)] } else { [--yes=($yes)] })
        let code = span $"stage ($step)" {} {
            try {
                if $step == "config" { open --raw $secrets | ^$NU_ROOT --no-config-file $entry $step ...$flags } else { ^$NU_ROOT --no-config-file $entry $step ...$flags }
                0
            } catch {|e| $e.exit_code? | default 1 }
        }
        let lines = file-lines $FAILURES
        let lines = if $step == "packages" and $code != 0 and ($lines | is-empty) { [$"($PACKAGES_FAILED): exited ($code)"] } else { $lines }
        $rows = $rows | append {stage: $step, code: $code, failures: $lines}
    }
    $rows
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

# The modules of an install-stage role (meta.phase): early runs before the install pass with packages unchecked
# (pacman.conf, the mirror's key) and again after it, never in config; install runs again after the pass.
def phase-ids [ctx: record, phase: string]: nothing -> list<string> {
    $ctx.modules | where {|m| $m.meta.phase? == $phase and $m.cfg.enable and not $m.broken } | get id
}

# --packages-unchecked: runs even before the module's packages are installed (base/pacman, ahead of the install pass).
def module-system [ctx: record, id: string, --packages-unchecked]: nothing -> bool {
    let planned = pipeline-plan $ctx system [$id] false --packages-unchecked=$packages_unchecked
    let results = pipeline-apply $ctx $planned system 1
    pending-save $planned.id $results
    $results | all { $in.ok }
}

# Never --wrapped: nu evaluates a wrapped main's `--flag=(expr)` arguments before its body runs, as root here.
def main [] {
    error make {msg: $"system-apply.nu <apply|install|config|packages|module|migrate|preserve-prune|set>"}
}

# apply <sha> <install|config|sync>: unpack the repo and secrets archive on stdin, run the stage's steps from the new
# copy in this one root entry (sync: the install pass, undeclared packages, config), and leave what each ended with in
# SYSTEM_STAGES for the run that asked (--run, its id). The report is gone from before the unpack until every step
# ended, so a copy that equals the checkout never vouches for steps an interrupt or a power cut kept from running. The
# archive is the user's working tree, uncommitted edits included, on purpose: the YubiKey or fingerprint prompt that
# started this as root is the gate, not a commit.
def "main apply" [sha: string, stage: string, --run: string = "", --unattended, --force, --yes]: nothing -> nothing {
    repo-guard | ignore
    if $stage not-in ($STAGES | columns) { error make {msg: $"apply: ($stage) is none of ($STAGES | columns | str join ', ')"} }
    if $run != "" and not ($run =~ $RUN_ID) { error make {msg: "apply: --run is not a run id"} }
    locked
    run-open $"system ($stage)"
    log-debug $"system ($stage) for the run ($run)" {kind: run, target: $stage, user_run: $run}
    rm --force $SYSTEM_STAGES
    let rows = try {
        tmp-dir-run --parent $RUN_TMP {|work|
            ^tar -x --no-same-owner --no-same-permissions -C $work -f - repo.tar secrets.tar
            open --raw ($work | path join repo.tar) | system-unpack $SYSTEM_REPO $sha
            stages-run $stage ($work | path join secrets.tar) $unattended $force $yes
        }
    } catch {|e| run-journal; error make $e }
    {run: $run, root_run: $env.DOT_RUN_ID, stages: $rows} | to nuon | save-atomic $SYSTEM_STAGES
    run-journal
    exit (stages-exit $rows.code)
}

# set <target> <json value> [--default]: store a machine option or platform key in this machine's root-owned file under
# ROOT_OPTIONS_DIR, which dot set cannot write as the user; validated against this copy's specs, never the profile.
# The value is positional and parsed as json here, never a value-taking flag. Its system part is a later dot apply.
def "main set" [target: string, value: string, --default]: nothing -> nothing {
    let repo = repo-guard
    locked
    run-open "system set"
    try { root-store $repo $target (if $default { null } else { $value | from json }) $default } catch {|e| run-journal; error make $e }
    log-info $"set ($target)"
    run-journal
}

def root-file [file: any]: nothing -> path {
    if $file == null or not ($file | str starts-with $ROOT_OPTIONS_DIR) {
        error make {msg: $"set: this machine's file is ($file | default 'none'), not one of root's under ($ROOT_OPTIONS_DIR)"}
    }
    $file
}

def root-store [repo: path, target: string, value: any, default: bool]: nothing -> nothing {
    let prefix = $"($PLATFORM_TARGET)."
    if ($target | str starts-with $prefix) {
        let cell = $target | str substring ($prefix | str length).. | split row "."
        let spec = platform-spec $cell
        if $spec == null { error make {msg: $"set: the platform has no key ($cell | str join '.')"} }
        if $spec.fixed { error make {msg: $"set: ($target) is set at install"} }
        let file = root-file (platform-load $repo).file
        let bad = if $value == null { [] } else { platform-value-errors $repo $cell $value "dot set" }
        if ($bad | is-not-empty) { error make {msg: ($bad | str join "\n")} }
        let text = open --raw $file
        let updated = $text | options-nuon-set $cell $value --remove=($value == null)
        let errors = platform-errors $repo ($updated | from nuon) $file
        if ($errors | is-not-empty) { error make {msg: ($errors | str join "\n")} }
        if $updated != $text { $updated | save-atomic $file }
        return
    }
    let parts = $target | parse --regex '^(?<mod>.+)\.(?<key>[a-z][a-z0-9_]*)$' | get --optional 0
    if $parts == null { error make {msg: $"set: ($target) names no option"} }
    let ctx = pipeline-load $repo system
    let m = module-get $ctx $parts.mod
    let spec = options-schema $m | get --optional $parts.key
    if $spec == null { error make {msg: $"set: ($parts.mod) has no option ($parts.key)"} }
    if $spec.scope != "machine" { error make {msg: $"set: ($target) is a user option, the profile's"} }
    let bad = if $default { [] } else { option-value-errors $parts.mod $parts.key $spec $value "dot set" }
    if ($bad | is-not-empty) { error make {msg: ($bad | str join "\n")} }
    let file = root-file $ctx.platform.options_file
    if $parts.key == $OPTION_ENABLE and $value == true and not $default and not $m.selected {
        error make {msg: (enable-raised $parts.mod {name: "platform", file: $file})}
    }
    let text = if ($file | path exists) { open --raw $file } else { "{}\n" }
    let updated = $text | options-nuon-set [$parts.mod $parts.key] $value --remove=$default
    if $updated != $text { $updated | save-atomic $file }
}

# every declared package from [lsck0] in one pass, base/pacman first, base/yubikey last
def "main install" [--unattended, --yes]: nothing -> nothing {
    let repo = entry-begin install $unattended
    failures-begin $FAILURES
    # the install stage runs base/pacman's verb, so root's state is migrated before it, as config does
    migrations-run $repo system | ignore
    ^pacman-key --init
    ^pacman-key --populate archlinux
    let offline = (which nm-online | is-not-empty) and not (try { ^nm-online $"--timeout=($OFFLINE_WAIT_S)"; true } catch { false })
    if $offline { log-warn $"still offline after ($OFFLINE_WAIT_S)s" }
    let ctx = pipeline-load $repo system --progress
    # pipeline-apply records the failure itself
    for id in (phase-ids $ctx early) { if not (module-system $ctx $id --packages-unchecked) { exit $EXIT_ABORTED } }
    # a power cut mid-transaction leaves the lock, and every retry boot would fail on it
    if ($PACMAN_LOCK | path exists) and not (process-running pacman) { rm --force $PACMAN_LOCK }
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    # at a terminal a lab outage skips the packages now, not after DOWNLOAD_TRIES warnings: the config stage still runs
    # and a module missing a package stays pending; the unattended chain waits it out
    if not $unattended and not $offline and $ctx.platform.facts.homelab? == true and (mirror-silent) {
        log-warn $"the homelab mirror ($HOMELAB.mirror.lsck0) does not answer: packages skipped, what needs a new one stays pending until a dot sync once it does"
        exit $EXIT_PENDING
    }
    pacman-retry "the database sync" (if $offline { $OFFLINE_TRIES } else { $DOWNLOAD_TRIES }) -Syy --noconfirm
    # one package the mirror cannot resolve drops only itself and what needs it, never the whole pass
    let probe = {|targets|
        let r = with-env {LC_ALL: C} { ^pacman -Sp --noconfirm --print-format "%n" ...$targets | complete }
        {ok: ($r.exit_code == 0), output: ($r.stdout + $r.stderr | lines)}
    }
    let resolved = packages-resolve $declared.pacman $probe
    for d in ($resolved.dropped | where why != $NOT_ON_MIRROR) {
        fail $"($d.name): ($d.why), left out of this pass; what needs it stays pending"
    }
    let built = if ($LSCK0_DB | path exists) { ls $LSCK0_DB | get 0.modified } else { null }
    let missing = $resolved.dropped | where why == $NOT_ON_MIRROR | get name
    # base/pacman leaves [lsck0] out while the lab does not answer: what only it carries waits, its ask times kept
    let lsck0_on = open --raw $PACMAN_CONF | lines | any {|l| ($l | str trim) == $LSCK0_SECTION }
    let absent = if $lsck0_on { mirror-awaited $missing (ledger-get $LEDGER_AWAITED) $built (date now) } else {
        {awaited: $missing, failed: [], record: (ledger-get $LEDGER_AWAITED)}
    }
    ledger-set $LEDGER_AWAITED $absent.record
    for name in $absent.failed { fail $"($NOT_ON_MIRROR): ($name) \(no build since it was first asked for carries it: a typo, or its build failed\)" }
    if not $lsck0_on and ($absent.awaited | is-not-empty) {
        log-note $"[lsck0] left out while the homelab mirror does not answer: ($absent.awaited | str join ' ') wait for it, then dot sync"
    } else if ($absent.awaited | is-not-empty) {
        log-note $"($NOT_ON_MIRROR) yet, newer than its last build: ($absent.awaited | str join ' '); the next nightly build brings them, then dot sync"
    }
    let available = $resolved.kept
    let wanted = packages-wanted $available
    log-info $"sources: ($available | length) packages, ($wanted | length) to install in one pass, ($resolved.dropped | length) left out"
    # -uu moves pacstrap's packages onto the snapshot and a pin back onto an older one; --ask 4 replaces old names
    let upgrade = if $unattended or ($ctx.platform.facts.lsck0_snapshot | is-not-empty) { "-Suu" } else { "-Su" }
    pacman-retry "the install pass" $DOWNLOAD_TRIES $upgrade --needed --noconfirm --ask 4 ...$wanted
    date now | format date '%+' | save --force $INSTALL_PASS_FILE
    # a machine off the lab syncs without [lsck0] (base/pacman's lsck0-drop), so it has no database to record
    if ($LSCK0_DB | path exists) {
        let synced = ls $LSCK0_DB | get 0.modified | date to-timezone UTC | format date '%FT%TZ'
        ledger-set snapshot [$"($ctx.platform.facts.lsck0_snapshot | default latest) ($synced) (open --raw $LSCK0_DB | hash sha256)"]
    }
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
    # again now its packages are in: config leaves base/pacman out, so what its inputs gate (pacman-contrib's timer)
    # is planned here or not until the next install pass; unchanged inputs skip it
    for id in ((phase-ids $ctx early) ++ (phase-ids $ctx install)) { module-system $ctx $id | ignore }
    failures-end install
    if ($absent.awaited | is-not-empty) { exit $EXIT_PENDING }
}

# What of the handed secrets tar root deletes unread: every entry that is no regular file (a link could point anywhere)
# or that no module's meta.secrets and no wireguard fact names. handed: {name, type} relative to the tar's root.
export def secrets-refused [handed: list<record>, allowed: list<string>]: nothing -> list<string> {
    $handed | where {|f| $f.type != "file" or $f.name not-in $allowed } | get name
}

# Records which secrets this config stage was handed, so a later sync can tell unprivileged that root has the same.
def secrets-record [secrets: path]: nothing -> nothing {
    let held = ^find $secrets -type f -print0 | split row (char nul) | where $it != "" | path relative-to $secrets
    let group = if (group-exists $ADMIN_GROUP) { [-g $ADMIN_GROUP -m 640] } else { [-m 600] }
    ^install ...$group /dev/null $SYSTEM_SECRETS_DIGEST
    $"(secrets-digest $secrets $held)\n" | save --force --raw $SYSTEM_SECRETS_DIGEST
}

# every system verb; the secrets arrive as a tar on stdin into a tmpfs gone at exit
def "main config" [--unattended, --force]: nothing -> nothing {
    let repo = entry-begin config $unattended
    failures-begin $FAILURES
    # a pending migration converts root's state before any verb reads it, also without a sync
    migrations-run $repo system | ignore
    let ctx = pipeline-load $repo system --progress
    let run = tmp-dir-run --parent $RUN_TMP {|secrets|
        ^tar -x --no-same-owner --no-same-permissions -C $secrets -f -
        let allowed = system-secrets $repo $ctx.platform.facts.wireguard?
        let handed = ^find $secrets -mindepth 1 ! -type d -print0 | split row (char nul) | where $it != ""
            | each {|f| {name: ($f | path relative-to $secrets), type: ($f | path type)} }
        secrets-refused $handed $allowed | each { rm --force ($secrets | path join $in) } | ignore
        secrets-record $secrets
        $env.DOTFILES_SECRETS = $secrets
        let early = phase-ids $ctx early
        let planned = pipeline-plan $ctx system [] $force --progress | where id not-in $early
        let results = pipeline-apply $ctx $planned system 1
        # the install stage holds the early modules' lines
        pending-save $planned.id $results --full --keep $early
        {results: $results, waiting: ($results | any { $in.pending? != null })}
    }
    rm --force $ADDUSER_BIN
    $"#!/bin/sh\n[ \"$\(id -u\)\" = 0 ] || exec sudo \"$0\" \"$@\"\nexec /usr/bin/nu --no-config-file ($SYSTEM_REPO | path join $ENTRY) adduser \"$@\"\n" | save $ADDUSER_BIN
    ^chmod 755 $ADDUSER_BIN
    try { ledger-units $repo ($ctx.modules | where cfg.enable) system | ignore } catch {|e| fail $"ledger: disabling dropped units: ($e.msg)" }
    # last, so every initramfs and cmdline change of this run is rebuilt once, then signed and verified
    for b in (barriers-run $ctx $run.results $force | where not ok) { fail $"barrier of ($b.id): ($b.error)" }
    failures-end config
    if $run.waiting { exit $EXIT_PENDING }
}

# remove explicit packages no module declares, after a yes
def "main packages" [--yes, --plan, --unattended]: nothing -> nothing {
    let repo = entry-begin packages $unattended
    let ctx = pipeline-load $repo system
    let declared = modules-packages $repo $ctx.modules $ctx.platform
    if ($declared.incomplete | is-not-empty) {
        error make {msg: $"not removing anything, these modules declare no packages right now: ($declared.incomplete | str join ' ')"}
    }
    let found = packages-convergence $declared.pacman $ctx.platform.packages_keep
    if ($found.remove | is-empty) { return }
    print $"not declared by any module: ($found.remove | str join ' ')"
    if $plan or not ($yes or (tty-confirm $"remove these ($found.remove | length)?")) { return }
    let kept = packages-orphans-remove $found.resolved $found.remove
    if ($kept | is-not-empty) { log-info $"still needed by another package, kept as a dependency: ($kept | str join ' ')" }
}

# module <id>: that module's system verb alone, for running it by hand; the system verb is the only one root runs
def "main module" [id: string]: nothing -> nothing {
    let repo = entry-begin module
    let ctx = pipeline-load $repo system
    if "system" not-in ($ctx.modules | where id == $id | get --optional 0.native | default []) { error make {msg: $"($id) has no native system verb"} }
    if not (module-system $ctx $id) { exit 1 }
}

def "main migrate" [--baseline]: nothing -> nothing {
    let repo = entry-begin migrate
    migrations-run $repo system --baseline=$baseline | ignore
}

def "main preserve-prune" [days: int]: nothing -> nothing {
    repo-guard | ignore
    locked
    preserve-prune $days
}

# banner-clear: a failed config stage's login banner, once the asking run applied both layers without a failure; here
# and not a bare rm, so polkit's kept approval of this entry covers it
def "main banner-clear" []: nothing -> nothing {
    repo-guard | ignore
    rm --force $CONFIG_ISSUE
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
        ^runuser -u $name -- git clone --filter=blob:none $dotfiles_url $checkout
        let gnupg = ^runuser -u $name -- mktemp -d | str trim
        ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" gpg --batch --quiet --import ($repo | path join $key_file)
        let status = ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" git -C $checkout verify-commit --raw HEAD | complete
        # the import started gpg-agent and scdaemon on the throwaway home; left running, scdaemon holds the card reader
        ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" gpgconf --kill all | complete | ignore
        ^runuser -u $name -- env $"GNUPGHOME=($gnupg)" gpgconf --remove-socketdir | complete | ignore
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
        profile-owner-add $name
    }
    ^systemd-run --quiet --wait --pipe --collect $"--uid=($name)" -p PAMName=login -p $"WorkingDirectory=($checkout)" nu --no-config-file scripts/dot.nu apply --packages --user
}
