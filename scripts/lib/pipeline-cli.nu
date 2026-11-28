#!/usr/bin/env -S nu --no-config-file
# dot plan, apply and status, which dot.nu hands straight to: this process parses only the pipeline, run and doctor,
# not the whole CLI, since every call of a closure-taking command costs per command the process parsed. The signatures
# are dot-cli.nu's, which carries their help and completion (dot.nu sends a --help there); misuse (a word the signature
# does not take, an unknown module, flags that contradict) is turned away here, in dot's own form.

const REPO = path self ../..
use log.nu *
use cli.nu [build guarded flag rows-out self-argv]
use usage.nu [counted die command-table words-misuse]
use modules.nu [modules-graph modules-packages modules-known]
use pipeline.nu [pipeline-load pipeline-plan]
use ledger.nu [packages-convergence]
use migrate.nu [migrations-pending]
use preserve.nu [preserve-report]
use doctor.nu [doctor-run doctor-checks]
use run.nu [plan-print link-plan tee-log admin apply-finish apply-run user-locked install-run link-run user-packages-undeclared pending-read managed-drift]

# the message tags of dot plan's package reports: the other layer's, loaded in a job while it plans, and the planned
# layer's, computed in a job beside the plan
const PLAN_OTHER_TAG = 1
const PLAN_OWN_TAG = 2

def main []: nothing -> nothing { help main }

# What a module waits for, a group it waits for whole as <group>/*: base alone is some thirty ids on every row.
def after-short [after: list<string>, groups: table]: nothing -> list<string> {
    let whole = $groups | where {|g| $g.ids | all { $in in $after } }
    ($whole | each { $"($in.group)/*" }) ++ ($after | where $it not-in ($whole.ids | flatten))
}

# What dot plan reports of a layer's packages: the system layer's pacman packages no module declares, the user
# layer's flatpak and nix ones (none checked while a module's packages hook failed).
def packages-report [ctx: record]: nothing -> record {
    let declared = with-env {DOT_LAYER: $ctx.layer} { modules-packages $REPO $ctx.modules $ctx.platform }
    if $ctx.layer == "system" {
        {layer: system, remove: (packages-convergence $declared.pacman $ctx.platform.packages_keep).remove}
    } else if ($declared.incomplete | is-not-empty) {
        {layer: user, incomplete: $declared.incomplete, undeclared: null}
    } else {
        {layer: user, incomplete: [], undeclared: (user-packages-undeclared $declared $ctx.platform)}
    }
}

def "main plan" [...mods: string, --system, --force, --order, --modules, --json]: nothing -> any {
    modules-known $REPO $mods
    let layer = if $system { "system" } else { "user" }
    if $order or $modules {
        return (guarded plan --read-only {
            let ctx = pipeline-load $REPO $layer
            let rows = if $order {
                let verb = if $system { "system" } else { "link" }
                let ran = $ctx.modules | where {|m| $verb in $m.verbs and $m.cfg.enable }
                let groups = $ran | where group != "" | group-by group | items {|group, members| {group: $group, ids: $members.id} }
                modules-graph $REPO $ran | select level id after
                | update after {|row| if $json { $row.after } else { after-short $row.after $groups } | str join " " }
            } else {
                $ctx.modules | each {|m|
                    {id: $m.id, kind: (if ($m.native | is-empty) { "packages" } else { "native" }), verbs: ($m.verbs | str join " "), enabled: $m.cfg.enable, packages: ($m.meta.packages.pacman | length)}
                }
            }
            if $json { $rows | to json } else { $rows | rows-out }
        })
    }
    guarded plan --read-only {
        # read before pipeline-load switches DOT_LAYER: the pending list lives in the user's state
        let waiting = pending-read
        # each layer loads once, and its package report (a packages hook child per layer, pacman, flatpak and nix
        # queries) needs nothing the plan decides: the other layer loads and reports in one job, the planned layer's
        # report runs in another beside the plan
        let other = if $system { "user" } else { "system" }
        job spawn {
            try { {report: (packages-report (pipeline-load $REPO $other))} } catch {|e| {error: $e.msg} } | job send 0 --tag $PLAN_OTHER_TAG
        } | ignore
        let planned_ctx = pipeline-load $REPO $layer
        job spawn {
            try { {report: (packages-report $planned_ctx)} } catch {|e| {error: $e.msg} } | job send 0 --tag $PLAN_OWN_TAG
        } | ignore
        if $system {
            plan-print (pipeline-plan $planned_ctx system $mods $force) system $planned_ctx.modules $mods
        } else {
            let planned = link-plan $planned_ctx $mods $force
            plan-print $planned link $planned_ctx.modules $mods
        }
        let pending = migrations-pending $REPO $layer
        if ($pending | is-not-empty) { print $"migrations pending: ($pending.id | str join ' ')" }
        if ($waiting | is-not-empty) { print $"system part pending for: ($waiting | str join ' '); dot apply runs it" }
        let report = {|tag|
            let got = job recv --tag $tag
            if $got.error? != null { error make {msg: $got.error} }
            $got.report
        }
        let extra = do $report (if $system { $PLAN_OWN_TAG } else { $PLAN_OTHER_TAG })
        if ($extra.remove | is-not-empty) {
            print $"installed, declared by no module \(($extra.remove | length)\): ($extra.remove | str join ' ')\n  dot apply --packages removes them after a yes"
        }
        let user = do $report (if $system { $PLAN_OTHER_TAG } else { $PLAN_OWN_TAG })
        if ($user.incomplete | is-not-empty) {
            print $"flatpak and nix: dot apply --packages removes none, these modules declare none: ($user.incomplete | str join ' ')"
            return
        }
        let undeclared = $user.undeclared
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
    if ($mods | is-not-empty) and $system { die --misuse "dot apply --system takes no modules: a module converges its user layer" }
    if $packages and ($mods | is-not-empty) { die --misuse "dot apply --packages takes no modules" }
    if $packages and $system and not $user { die --misuse "dot apply --packages runs both layers, or --user alone" }
    modules-known $REPO $mods
    if $no_system { $env.DOT_SYSTEM = "skip" }
    user-locked
    let one = if $user and $system { "" } else if $user or ($mods | is-not-empty) { "user" } else if $system { "system" } else { "" }
    if $packages {
        tee-log install ([apply --packages] ++ (flag user ($one == "user")) ++ (flag yes $yes) ++ (flag force $force))
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
            tee-log config ([apply --system] ++ (flag force $force))
            guarded apply {
                if not (admin) { error make {msg: "apply --system: the system layer is root's, and this login is not in wheel"} }
                apply-run true false $force | apply-finish $in
            }
        }
        _ => {
            tee-log config ([apply] ++ (flag force $force))
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
        system_pending: (pending-read)
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
        print $"last run ($head.last_run), (counted $head.errors error)"
        if ($head.migrations_pending | is-not-empty) { print $"migrations pending: ($head.migrations_pending | str join ' ')" }
        if ($head.system_pending | is-not-empty) { print $"system part pending: ($head.system_pending | str join ' '); dot apply runs it" }
        $drift | where pending | each { print $"pending apply: ($in.target) \(($in.module), ($in.drift)\); dot apply puts it back" } | ignore
        $drift | where not pending | each { print $"changed since its apply: ($in.target) \(($in.module), ($in.drift)\); dot module adopt or apply --force" } | ignore
        print ""
        let failed = doctor-run
        if $failed { exit 1 }
    }
}

# nushell parses the words against a command's signature before any command here runs, and answers a mistyped flag
# with its parser's frame; this top-level check runs first and answers in dot's own form, as dot-cli.nu does
let words = self-argv | skip 1 | skip while { $in | str starts-with "-" } | skip 1
if ($words | is-not-empty) {
    let misuse = words-misuse (command-table) $words []
    if $misuse != null { die --misuse $misuse }
}
