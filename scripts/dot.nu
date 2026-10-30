#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname | path dirname
const LIB = $REPO | path join scripts lib
use ($LIB | path join log.nu) *
use ($LIB | path join cli.nu) [concat build guarded]
use ($LIB | path join usage.nu) [die]
use ($LIB | path join complete.nu) [command-table module-ids option-keys option-values theme-names run-ids]
use ($LIB | path join state.nu) [state-dir SYSTEM_STATE]
use ($LIB | path join platform.nu) [platform-env]
use ($LIB | path join modules.nu) [modules-graph modules-packages modules-eval]
use ($LIB | path join pipeline.nu) [pipeline-load pipeline-plan pipeline-apply]
use ($LIB | path join preserve.nu) [preserve-report tty-confirm]
use ($LIB | path join ledger.nu) [packages-convergence PACKAGES_DENY]
use ($LIB | path join migrate.nu) [migrations-pending]
use ($LIB | path join gate.nu) [gate-lint gate-tools gate-palette]
use ($LIB | path join vm.nu) [USER PROFILE PLATFORM vm-run vm-destroy screenshot]
use ($REPO | path join configs base yubikey yubikey.nu) [yubikey-init yubikey-seal yubikey-unlock yubikey-lock]
use ($REPO | path join configs base yubikey audit.nu) [audit-run audit-rotated audit-drilled]
use ($LIB | path join doctor.nu) [doctor-run doctor-checks]
use ($REPO | path join configs core wallust wallpaper.nu) [wallpaper-set wallpaper-random wallpaper-pick]
use ($LIB | path join sync.nu) [sync-commit sync-can-sign]
use ($LIB | path join run.nu) [plan-print link-run failures-publish finish admin system-allowed pty-log system-skipped pending-exit apply-run user-locked unlink-run install-run user-packages-undeclared pending-file system-part update-run managed-drift INTERNAL]
use ($LIB | path join set.nu) [options-list option-target option-write option-apply]

const USAGE = "dot: this machine as code. `dot sync` brings it to what the repo prescribes and records it

  sync [--no-push]                pull, migrate, install, apply, back up, commit the signed generation, push
  apply [mod...]                  converge now, no git: system layer, then user layer; modules: their user layer
    --user | --system             one layer
    --packages                    declared packages, flatpak and nix, then the apply; undeclared ones go after a yes
  plan [mod...]                   what an apply would do; --order the run order, --modules every module
  status [--brief|--json]         generation, pending work, failures, changed files, health checks, secrets
  set [mod[.key] [value]]         options: every set one, a module's, one; a value sets it, --default resets it
  theme [name|random]             wallpaper and theme, fzf without a name
  module adopt|reset <file>       a changed file: into the repo | back to the repo copy
  module unlink|remove|restore    a module: off | gone with its packages | its restore verb (app state)
  log [run] | explain <thing>     a run's records | who wrote a path, who declares a package
  secrets unlock|lock|init|seal|audit
  test lint|check|fmt|run|...     the gates and the vm test

  --no-system on sync, apply, set: only the user part, same as DOT_SYSTEM=skip
  dot <command> --help for its flags"

const LOG_LEVELS = [TRACE DEBUG INFO WARN ERROR PANIC]

# this machine as code; `dot sync` brings it to what the repo prescribes
def --wrapped main [...args: string]: nothing -> nothing {
    let word = $args | get --optional 0
    if $word == null or $word in [--help -h help] {
        print $USAGE
        return
    }
    die --misuse $"unknown command '($word)', dot lists them"
}

# what an apply would do, touching nothing
def "main plan" [
    ...mods: string@module-ids
    --system   # the system layer
    --force    # as an apply --force would
    --order    # each enabled module with its level and what it waits for
    --modules  # every module: kind, verbs, whether this machine runs it
    --json     # --order or --modules as json
]: nothing -> any {
    if $order or $modules {
        return (guarded plan --read-only {
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
    guarded plan --read-only {
        # read before pipeline-load switches DOT_LAYER: the pending list lives in the user's state
        let waiting = try { open --raw (pending-file) | lines | uniq } catch { [] }
        if $system {
            let ctx = pipeline-load $REPO system
            plan-print (pipeline-plan $ctx system $mods $force) system $ctx.modules $mods
        } else {
            link-run $mods $force true | ignore
        }
        let pending = migrations-pending $REPO (if $system { "system" } else { "user" })
        if ($pending | is-not-empty) { print $"migrations pending: ($pending.id | str join ' ')" }
        if ($waiting | is-not-empty) { print $"system part pending for: ($waiting | str join ' '); dot apply runs it" }
        let ctx = pipeline-load $REPO system
        let declared = modules-packages $REPO $ctx.modules $ctx.platform
        let extra = packages-convergence $declared.pacman $ctx.platform.packages_keep
        if ($extra.remove | is-not-empty) {
            print $"installed, declared by no module \(($extra.remove | length)\): ($extra.remove | str join ' ')\n  dot apply --packages removes them after a yes"
        }
        let user = pipeline-load $REPO user
        let declared_user = modules-packages $REPO $user.modules $user.platform
        if ($declared_user.incomplete | is-not-empty) {
            print $"flatpak and nix: dot apply --packages removes none, these modules declare none: ($declared_user.incomplete | str join ' ')"
            return
        }
        let undeclared = user-packages-undeclared $declared_user $user.platform
        for kind in [flatpak nix] {
            let diff = $undeclared | get $kind
            if ($diff.dropped | is-not-empty) { print $"($kind), declared by no module any more: ($diff.dropped | str join ' ')\n  dot apply --packages removes them after a yes" }
            if ($diff.by_hand | is-not-empty) {
                print $"($kind), installed by hand, declared by no module \(($diff.by_hand | length)\): ($diff.by_hand | str join ' ')\n  dot apply --packages removes them after a yes, ($kind)_keep in the platform spares them"
            }
        }
    }
}

def flag [name: string, on: bool]: nothing -> list<string> {
    if $on { [$"--($name)"] } else { [] }
}

# converge now, no git: system layer from the root-owned copy, then user layer; modules: only their user layer
def "main apply" [
    ...mods: string@module-ids
    --user       # the user layer alone
    --system     # the system layer alone
    --packages   # declared packages, flatpak and nix, then the apply; undeclared ones go after a yes
    --force      # overwrite drift, the live copy preserved aside
    --yes        # with --packages: remove undeclared packages unasked; hand-installed flatpak and nix still ask
    --no-system  # only the user part, same as DOT_SYSTEM=skip
]: nothing -> nothing {
    if $no_system { $env.DOT_SYSTEM = "skip" }
    user-locked
    let one = if $user and $system { "" } else if $user or ($mods | is-not-empty) { "user" } else if $system { "system" } else { "" }
    if ($mods | is-not-empty) and $system { die --misuse "apply: modules converge their user layer, --system takes none" }
    if $packages {
        if ($mods | is-not-empty) { die --misuse "apply --packages takes no modules" }
        if $one == "system" { die --misuse "apply --packages: both layers, or --user alone" }
        pty-log install ([apply --packages] ++ (flag user ($one == "user")) ++ (flag yes $yes) ++ (flag force $force))
        let pending = guarded apply {
            let status = install-run ($one == "user") $yes true
            if $status != 0 { exit $status }
            $env.DOT_SYSTEM_PENDING? == true
        }
        if $pending { $env.DOT_SYSTEM_PENDING = true }
    }
    match $one {
        "user" => {
            guarded apply { link-run $mods $force false | finish $in }
            pending-exit
        }
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

# one module by hand: adopt, reset, unlink, remove, restore
def "main module" []: nothing -> nothing { help main module }

# reverse a native module's last apply; files changed since stay, originals come back
def "main module unlink" [mod: string@module-ids]: nothing -> nothing {
    user-locked
    guarded unlink { unlink-run $mod | finish $in }
}

# unlink a module, turn it off (--machine: for the machine), offer its packages for removal
def "main module remove" [mod: string@module-ids, --machine, --yes]: nothing -> nothing {
    user-locked
    guarded remove {
        let ctx = pipeline-load $REPO user
        let m = $ctx.modules | where id == $mod | get --optional 0
        if $m == null { error make {msg: $"no module ($mod); dot plan --modules lists them"} }
        let dependents = $ctx.modules | where {|d| $d.cfg.enable and $mod in $d.meta.deps } | get id
        if ($dependents | is-not-empty) { error make {msg: $"($dependents | str join ', ') depend on ($mod), remove those first"} }
        if ($m.native | is-not-empty) { unlink-run $mod | ignore }
        option-write $mod enable false $machine | ignore
        if $machine and "system" in $m.verbs and (admin) { system-part $"($mod).enable" }
        let declared = modules-packages $REPO ($ctx.modules | where id != $mod) $ctx.platform
        if ($declared.incomplete | is-not-empty) {
            error make {msg: $"not offering packages for removal, these modules declare none right now: ($declared.incomplete | str join ' ')"}
        }
        let others = $declared.pacman
        let installed = ^pacman -Qq | lines
        let own = $m.meta.packages.pacman ++ (if $ctx.platform.form_factor == "wsl" { [] } else { $m.meta.packages.native })
        # the same spares as the ledger's removal: dot itself, the shell and the boot chain never go
        let only = $own | where {|p| $p not-in $others and $p in $installed and not ($p =~ $PACKAGES_DENY) }
        if not $machine and ($only | is-not-empty) {
            print $"($mod) stays on for the system layer, its packages too; --machine turns it off machine-wide and offers them for removal"
        } else if ($only | is-not-empty) {
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
        let matches = $planned | get actions | concat | where target == $target and decl.kind == file
        let found = $matches | where {|a| $a.kind not-in [remove forget] and not ($a.reason | str starts-with "no longer declared") } | get --optional 0
        if $found == null and ($matches | is-not-empty) {
            error make {msg: $"($target) is no longer declared by ($matches.0.module), there is nothing to adopt it into; delete or keep it by hand"}
        }
        if $found == null { error make {msg: $"($target) is no file a module copies; dot status lists the changed ones"} }
        if $found.decl.source == null { error make {msg: $"($target) is rendered by ($found.module), adopt it by editing its template"} }
        ^cp $target $found.decl.source
        log-info $"($target) -> ($found.decl.source | path relative-to $REPO)"
    }
}

# put one changed managed file back to its module's copy, the edit preserved aside; the module's other files stay
def "main module reset" [file: path]: nothing -> nothing {
    user-locked
    guarded reset {
        let target = $file | path expand
        let ctx = pipeline-load $REPO user
        let planned = pipeline-plan $ctx link [] false
        let row = $planned | where {|m| $m.actions | any {|a| $a.target == $target and $a.decl.kind? == file } } | get --optional 0
        let current = if $row == null { null } else { $row.actions | where target == $target | first }
        if $current == null or $current.kind != drift {
            let managed = $planned | any {|m| $m.prev | any {|o| $o.target? == $target and $o.kind? == file } }
            if $row == null and not $managed { error make {msg: $"($target) is no file a module manages; dot status lists the changed ones"} }
            error make {msg: $"($target) is not changed since its apply, nothing to reset"}
        }
        # an orphan (a module that stopped declaring the file) has no source to put back
        if ($current.reason | str starts-with "no longer declared") {
            error make {msg: $"($target) is no longer declared by ($row.id), there is nothing to reset it to; delete or keep it by hand"}
        }
        let forced = pipeline-plan $ctx link [$row.id] true | where id == $row.id | first
        if $forced.error != null { error make {msg: $"reset ($target): ($forced.error)"} }
        let reset = $forced.actions | where target == $target | first
        if $reset.kind == drift { error make {msg: $"($target) stays drift even when forced: ($reset.reason)"} }
        let actions = $row.actions | each {|a| if $a.target == $target { $reset } else { $a } }
        let result = pipeline-apply $ctx [($row | update actions $actions | update after [])] link 1 | first
        if not $result.ok { error make {msg: $"reset ($target): ($result.error)"} }
        log-info $"($target) <- ($row.id), the edit kept aside: dot status lists preserved copies"
    }
}

# run one module's restore verb (state its link does not already restore)
def "main module restore" [mod: string@module-ids]: nothing -> nothing {
    user-locked
    guarded restore {
        let ctx = pipeline-load $REPO user
        let m = $ctx.modules | where id == $mod | get --optional 0
        if $m == null or "restore" not-in $m.native { error make {msg: $"($mod) has no restore verb"} }
        let r = with-env (platform-env $ctx.platform) { modules-eval [$m] restore {$m.id: $m.cfg} [] } | first
        if not $r.ok { error make {msg: $"restore ($mod): ($r.error)"} }
    }
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
    let write = $target != null and ($default or ($value | is-not-empty))
    if $write { user-locked }
    guarded set --read-only=(not $write) {
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
        let parsed = if ($value | describe) != "string" { $value } else { try { $value | from nuon } catch { try { $value | from json } catch { $value } } }
        option-apply $target (option-write $t.mod $t.key $parsed $machine)
    }
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

# the one command: pull, migrate, install, apply, back up app state, commit the signed generation, push
def "main sync" [
    --no-push    # stop after the apply: no backup, commit or push; a machine that does not sign always stops there
    --yes        # remove undeclared packages without asking; flatpak and nix installed by hand only apply --packages offers
    --no-system  # only the user part, same as DOT_SYSTEM=skip
    --no-verify  # commit without the formatter, linter and gitleaks gates
]: nothing -> nothing {
    if $no_system { $env.DOT_SYSTEM = "skip" }
    user-locked
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

def status-head []: nothing -> record {
    let last = run-last-changed
    let records = if $last == null { [] } else { open --raw $last | lines | each { from json } }
    {
        generation: (^git -C $REPO log -1 --format=%s | str trim)
        build: (build)
        last_run: (if $last == null { "none" } else { $last | path basename | str replace ".jsonl" "" })
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
    guarded status --read-only {
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
        if $failed { exit 1 }
    }
}

# a run's records (default the last) by module and level; --trace the span tree with timings
def "main log" [run?: string@run-ids, --module: string@module-ids, --level: string@$LOG_LEVELS = "INFO", --trace]: nothing -> any {
    if ($level | str uppercase) not-in $LOG_LEVELS { die --misuse $"log: --level ($level), one of ($LOG_LEVELS | str join ' ')" }
    let file = if $run == null { run-last-changed } else { runs-dir | path join $"($run).jsonl" }
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
    let rank = $LOG_LEVELS | enumerate | where item == ($level | str uppercase) | get 0.index
    $records | where {|r| ($LOG_LEVELS | enumerate | where item == $r.level | get 0.index) >= $rank }
    | where {|r| $module == null or $r.module == $module } | select time level module msg
}

# which module and run wrote a path, or which module declares a package
def "main explain" [thing: string]: nothing -> nothing {
    guarded explain --read-only {
        let target = if ($thing | str contains "/") { $thing | path expand --no-symlink } else { $thing }
        # both layers' records: root's are world-readable, a file the system layer writes has its writer there
        let owners = [(state-dir) $SYSTEM_STATE] | uniq | each {|dir|
            let root = $dir | path join modules
            glob ($root | path join **/*.nuon) | each {|f|
                let st = try { open $f } catch { {outputs: []} }
                $st.outputs | where target == $target | each { {module: ($f | path dirname | path relative-to $root), verb: ($f | path parse | get stem), output: $in, run: $st.run?, time: $st.time?} }
            } | flatten
        } | flatten
        let declares = if $target != $thing { [] } else {
            pipeline-load $REPO user | get modules | where {|m|
                let p = $m.meta.packages
                $thing in ($p.pacman ++ $p.native ++ $p.nix ++ ($p.flatpak | columns))
            } | get id
        }
        if ($owners | is-empty) and ($declares | is-empty) { error make {msg: $"nothing owns ($thing)"} }
        $owners | each {|o| print $"($o.module) ($o.verb): ($o.output.kind) ($o.output.target)(if $o.output.source? != null { $' from ($o.output.source)' } else { '' }), run ($o.run) at ($o.time)" } | ignore
        $declares | each { print $"($in) declares the package ($thing)" } | ignore
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

# the static gates (lint, check, fmt) and the vm test (run, shot, destroy)
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

# end-to-end vm test from the lsck0 iso, hours; --master tests github master; logs in $XDG_CACHE_HOME/vm-test/<name>
def "main test run" [--iso: path, --platform: string, --user: string, --profile: string, --master, --name: string = $VM_NAME]: nothing -> nothing {
    guarded test {
        let problems = gate-lint
        if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
        vm-run $name $iso ($platform | default $PLATFORM) ($user | default $USER) ($profile | default $PROFILE) $master
    }
}

# screenshot of the test vm to $XDG_CACHE_HOME/vm-test/<name>/screen.png
def "main test shot" [--name: string = $VM_NAME]: nothing -> nothing { guarded test { print (screenshot $name) } }

# delete the test vm and its disk
def "main test destroy" [--name: string = $VM_NAME]: nothing -> nothing { guarded test { vm-destroy $name } }

# the git-crypt worktree behind the yubikey
def "main secrets" []: nothing -> nothing { help main secrets }
# enroll a yubikey for secrets (every step, or the named ones)
def "main secrets init" [...steps: string]: nothing -> nothing { guarded secrets { yubikey-init ...$steps } }
# re-seal the git-crypt key to every enrolled key's recipient
def "main secrets seal" []: nothing -> nothing { guarded secrets { yubikey-seal } }
# pull and unlock configs/secrets/ with a touch of the yubikey, or --identity <age file> without one
def "main secrets unlock" [--identity: path]: nothing -> nothing { guarded secrets { yubikey-unlock --identity=$identity } }
# lock configs/secrets/ again
def "main secrets lock" []: nothing -> nothing { guarded secrets { yubikey-lock } }
# what is due for rotation or a recovery drill
def "main secrets audit" [--brief]: nothing -> nothing { guarded audit --read-only { audit-run --brief=$brief } }
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
