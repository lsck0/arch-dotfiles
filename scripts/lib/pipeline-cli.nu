#!/usr/bin/env -S nu --no-config-file
# dot plan, apply and status, which dot.nu hands off to: this process parses only the pipeline, run and doctor, not the
# whole CLI, since every call of a closure-taking command costs per command the process parsed. The signatures are
# dot.nu's, which carries their help and completion.

const REPO = path self ../..
use log.nu *
use cli.nu [build guarded flag]
use usage.nu [die]
use modules.nu [modules-graph modules-packages]
use pipeline.nu [pipeline-load pipeline-plan]
use ledger.nu [packages-convergence]
use migrate.nu [migrations-pending]
use preserve.nu [preserve-report]
use doctor.nu [doctor-run doctor-checks]
use run.nu [plan-print link-plan pty-log admin apply-finish apply-run user-locked install-run link-run user-packages-undeclared pending-file managed-drift]

# the message tag of the layer context dot plan loads in a job while it plans the other
const PLAN_OTHER_TAG = 1

def main []: nothing -> nothing { help main }

def "main plan" [...mods: string, --system, --force, --order, --modules, --json]: nothing -> any {
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
        # each layer loads once: the plan's context is reused for the packages below, the other one loads alongside
        let other = if $system { "user" } else { "system" }
        job spawn {
            try { {ctx: (pipeline-load $REPO $other)} } catch {|e| {error: $e.msg} } | job send 0 --tag $PLAN_OTHER_TAG
        } | ignore
        let planned_ctx = if $system { pipeline-load $REPO system } else { pipeline-load $REPO user }
        let other_ctx = {||
            let got = job recv --tag $PLAN_OTHER_TAG
            if $got.error? != null { error make {msg: $got.error} }
            $got.ctx
        }
        if $system {
            plan-print (pipeline-plan $planned_ctx system $mods $force) system $planned_ctx.modules $mods
        } else {
            let planned = link-plan $planned_ctx $mods $force
            plan-print $planned link $planned_ctx.modules $mods
        }
        let pending = migrations-pending $REPO (if $system { "system" } else { "user" })
        if ($pending | is-not-empty) { print $"migrations pending: ($pending.id | str join ' ')" }
        if ($waiting | is-not-empty) { print $"system part pending for: ($waiting | str join ' '); dot apply runs it" }
        let ctx = if $system { $planned_ctx } else { do $other_ctx }
        let declared = with-env {DOT_LAYER: system} { modules-packages $REPO $ctx.modules $ctx.platform }
        let extra = packages-convergence $declared.pacman $ctx.platform.packages_keep
        if ($extra.remove | is-not-empty) {
            print $"installed, declared by no module \(($extra.remove | length)\): ($extra.remove | str join ' ')\n  dot apply --packages removes them after a yes"
        }
        let user = if $system { do $other_ctx } else { $planned_ctx }
        let declared_user = with-env {DOT_LAYER: user} { modules-packages $REPO $user.modules $user.platform }
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

def "main apply" [...mods: string, --user, --system, --packages, --force, --yes, --no-system]: nothing -> nothing {
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
            guarded apply { link-run $mods $force --user-only | apply-finish $in }
        }
        "system" => {
            pty-log config ([apply --system] ++ (flag force $force))
            guarded apply {
                if not (admin) { error make {msg: "apply --system: the system layer is root's, and this login is not in wheel"} }
                apply-run true false $force | apply-finish $in
            }
        }
        _ => {
            pty-log config ([apply] ++ (flag force $force))
            guarded apply { apply-run true true $force | apply-finish $in }
        }
    }
}

def status-head []: nothing -> record {
    let last = run-last-changed
    let records = if $last == null { [] } else { run-records $last }
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

def "main status" [--brief, --json]: nothing -> nothing {
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
