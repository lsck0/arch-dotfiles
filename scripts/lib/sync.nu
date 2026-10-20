use log.nu *
use secrets.nu [secret-is-plaintext secrets-wanted]

const BRANCH = "master"
const PUSH_TRIES = 3
const FINGERPRINT_LINE = '(?m)^SIGNING_KEY_FINGERPRINT=(?<fpr>[0-9A-F]{40})$'

# a rollback leaves a detached HEAD at an old generation; a commit there is off master and the push fails
export def sync-branch-check [repo: path]: nothing -> nothing {
    if (try { ^git -C $repo symbolic-ref -q --short HEAD | str trim } catch { "" }) != $BRANCH {
        error make {msg: $"HEAD is not on ($BRANCH), go back with: git switch ($BRANCH)"}
    }
}

# local edits ride along; one that conflicts with the pulled generation stops the run before anything applies;
# without the secrets capability no submodule is fetched, so the private secrets remote is never asked
export def sync-pull [repo: path]: nothing -> nothing {
    sync-branch-check $repo
    let recurse = if (secrets-wanted) { [] } else { [--no-recurse-submodules] }
    try { ^git -C $repo pull --ff-only --autostash ...$recurse } catch {
        error make {msg: $"git pull --ff-only failed: offline, or ($BRANCH) diverged from origin \(git -C ($repo) pull --rebase\)"}
    }
    let conflicts = ^git -C $repo diff --name-only --diff-filter=U | lines
    if ($conflicts | is-not-empty) {
        error make {msg: $"local edits conflict with the pulled generation: ($conflicts | str join ' '); resolve them, then git stash drop"}
    }
    secrets-follow $repo
}

# the pulled generation may name a newer secrets revision; the commit's `git add .` would record the old checkout back
def secrets-follow [repo: path]: nothing -> nothing {
    let secrets = $repo | path join secrets
    if not (secrets-wanted) or not ($secrets | path join .git | path exists) { return }
    let recorded = ^git -C $repo ls-tree HEAD secrets | parse --regex '^\S+ commit (?<sha>[0-9a-f]+)' | get --optional 0.sha
    let current = ^git -C $secrets rev-parse HEAD | str trim
    if $recorded == null or $recorded == $current { return }
    if (^git -C $secrets cat-file -e $"($recorded)^{commit}" | complete).exit_code != 0 {
        try { ^git -C $secrets fetch --quiet origin } catch { error make {msg: "secrets: fetch failed, the pulled generation names a revision this checkout lacks"} }
    }
    if (^git -C $secrets merge-base --is-ancestor $recorded $current | complete).exit_code == 0 { return }
    if (^git -C $secrets merge-base --is-ancestor $current $recorded | complete).exit_code != 0 {
        error make {msg: $"secrets: ($current) and the pulled ($recorded) diverged, merge them in ($secrets)"}
    }
    try { ^git -C $secrets checkout --quiet $recorded } catch {
        error make {msg: $"secrets: local edits conflict with the pulled revision ($recorded), commit or move them in ($secrets)"}
    }
}

def fingerprint [repo: path]: nothing -> string {
    let fpr = open --raw ($repo | path join bootstrap.sh) | parse --regex $FINGERPRINT_LINE | get fpr
    if ($fpr | length) != 1 { error make {msg: "bootstrap.sh has no single SIGNING_KEY_FINGERPRINT=<40 hex>"} }
    $fpr.0
}

export def sync-can-sign [repo: path]: nothing -> bool {
    (^gpg --batch --list-secret-keys (fingerprint $repo) | complete).exit_code == 0
}

export def sync-commit [repo: path, --no-verify]: nothing -> nothing {
    sync-branch-check $repo
    let fpr = fingerprint $repo
    if not (sync-can-sign $repo) {
        error make {msg: $"no secret key ($fpr) to sign with, so no generation from this machine: dot secrets unlock && dot apply --user imports it"}
    }

    ^nu --no-config-file ($repo | path join scripts lib internal.nu) backup
    # secrets first, so the generation commit records its new revision
    let secrets = $repo | path join secrets
    if (secrets-wanted) and (secret-is-plaintext ($secrets | path join pgp_privatekey.asc)) {
        if (^git -C $secrets status --porcelain | str trim | is-not-empty) {
            ^git -C $secrets add -A
            ^git -C $secrets commit -m "chore(sync): back up live app state"
        }
        # submodule update leaves a detached HEAD, so push it to the branch explicitly; another machine's backup may
        # have landed since the pull: rebase onto it (only a blob both changed conflicts) and try again
        mut tries = 0
        while (^git -C $secrets push origin $"HEAD:($BRANCH)" | complete).exit_code != 0 {
            $tries += 1
            if $tries > $PUSH_TRIES { error make {msg: $"secrets: push still rejected after ($PUSH_TRIES) rebases"} }
            ^git -C $secrets fetch --quiet origin
            if (^git -C $secrets rebase $"origin/($BRANCH)" | complete).exit_code != 0 {
                ^git -C $secrets rebase --abort
                error make {msg: $"secrets: this machine's backup and origin/($BRANCH) changed the same file, resolve it in ($secrets)"}
            }
        }
    }

    # the apply took minutes: take what another machine pushed meanwhile, so the generation number follows it
    sync-catch-up $repo
    ^git -C $repo add .
    if (^git -C $repo diff --cached --quiet | complete).exit_code == 0 {
        log-info "sync: nothing changed, no new generation"
    } else {
        # bootstrap.sh and the lsck0 builder consume master directly: a script that does not parse never becomes a generation
        let broken = ^git -C $repo ls-files -z '*.sh' | split row (char nul) | where $it != "" | par-each {|f| if (^bash -n ($repo | path join $f) | complete).exit_code != 0 { $f } } | compact
        if ($broken | is-not-empty) { error make {msg: $"does not parse, nothing committed: ($broken | str join ' ')"} }
        # master is public: a credential in any tracked file must never get there; secrets/ is encrypted and allowlisted
        if not $no_verify {
            try { ^nu --no-config-file ($repo | path join scripts dot.nu) test check } catch { error make {msg: "dot test check found a problem, nothing committed (dot sync --no-verify overrides)"} }
            try { do { cd $repo; ^gitleaks git --staged --redact --no-banner } } catch { error make {msg: "gitleaks found a secret in the staged tree, nothing committed (dot sync --no-verify overrides)"} }
        }
        generation-commit $repo $fpr
    }
    # a push lost to another machine by seconds: undo the local generation, catch up, commit it again on top
    mut tries = 0
    while (^git -C $repo push --no-recurse-submodules | complete).exit_code != 0 {
        $tries += 1
        if $tries > $PUSH_TRIES { error make {msg: $"push still rejected after ($PUSH_TRIES) retries"} }
        ^git -C $repo reset --soft HEAD~1
        ^git -C $repo stash push --quiet --include-untracked
        sync-catch-up $repo
        ^git -C $repo stash pop --quiet
        ^git -C $repo add .
        generation-commit $repo $fpr
    }
}

def generation-commit [repo: path, fpr: string]: nothing -> nothing {
    let last = ^git -C $repo log --format=%s | parse --regex '(?m)^Generation: (?<n>\d+)' | get --optional 0.n | default "0" | into int
    ^git -C $repo -c gpg.format=openpgp commit $"-S($fpr)" -m $"Generation: ($last + 1)"
}

# fast-forward to origin; local edits are only in the worktree at this point, never a local commit
def sync-catch-up [repo: path]: nothing -> nothing {
    ^git -C $repo fetch --quiet --no-recurse-submodules origin
    if (^git -C $repo merge --ff-only --autostash $"origin/($BRANCH)" | complete).exit_code != 0 {
        error make {msg: $"($BRANCH) diverged from origin while syncing, nothing committed: git -C ($repo) pull --rebase"}
    }
}
