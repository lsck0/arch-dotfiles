# The git half of dot sync: verified pull, regenerated files, signed generation commit, push with retry.

use log.nu *
use secrets.nu [secret-is-plaintext secret-bytes-locked secrets-keys-chmod secrets-wanted OWNER_WITNESS]
use state.nu [state-dir]
use gate.nu [lint-stray]
use system.nu [bootstrap-const FINGERPRINT_VALUE]
use proc.nu [succeeds]

const BRANCH = "master"
const PUSH_TRIES = 3
const PUSH_REJECTED = "! [rejected]"
const SECRETS_GITLINK = "configs/secrets"
const LUKS_HEADER_MAX_AGE_DAYS = 90

# Fails unless HEAD is on master: a detached HEAD would commit off it and the push would fail.
export def sync-branch-check [repo: path]: nothing -> nothing {
    if (try { ^git -C $repo symbolic-ref -q --short HEAD | str trim } catch { "" }) != $BRANCH {
        error make {msg: $"HEAD is not on ($BRANCH), go back with: git switch ($BRANCH)"}
    }
}

# origin's head must carry the owner's signature (throwaway keyring): root runs it next.
def origin-verified [repo: path]: nothing -> nothing {
    let rev = $"origin/($BRANCH)"
    let gnupg = mktemp --directory
    # remove the throwaway keyring whether the import and verify succeed or throw
    let outcome = try {
        with-env {GNUPGHOME: $gnupg} {
            ^gpg --batch --quiet --import ($repo | path join (bootstrap-const $repo SIGNING_KEY_FILE))
            ^git -C $repo verify-commit --raw $rev | complete
        }
    } catch {|e| {failed: $e.msg} }
    # the agent gpg started keeps a socket dir under /run/user/<uid>/gnupg per keyring: stop it and remove that too
    with-env {GNUPGHOME: $gnupg} {
        ^gpgconf --kill all | complete | ignore
        ^gpgconf --remove-socketdir | complete | ignore
    }
    rm --recursive --force $gnupg
    if ($outcome | get --optional failed) != null { error make {msg: $outcome.failed} }
    let signer = $outcome.stderr | lines | where ($it | str contains "VALIDSIG") | get --optional 0 | default "" | split row " " | last
    if $outcome.exit_code != 0 or $signer != (fingerprint $repo) {
        error make {msg: $"($rev) is not signed by (fingerprint $repo), nothing merged: check git -C ($repo) log ($rev)"}
    }
}

# Fast-forwards with local edits autostashed; conflicts stop the run, the submodule is skipped without secrets.
export def sync-pull [repo: path]: nothing -> nothing {
    sync-branch-check $repo
    try { ^git -C $repo fetch --quiet --no-recurse-submodules origin } catch {
        error make {msg: "git fetch failed: offline?"}
    }
    origin-verified $repo
    try { ^git -C $repo merge --ff-only --autostash $"origin/($BRANCH)" } catch {
        error make {msg: $"git merge --ff-only failed: ($BRANCH) diverged from origin \(git -C ($repo) pull --rebase\)"}
    }
    let conflicts = ^git -C $repo diff --name-only --diff-filter=U | lines
    if ($conflicts | is-not-empty) {
        error make {msg: $"local edits conflict with the pulled generation: ($conflicts | str join ' '); resolve them, then git stash drop"}
    }
    secrets-follow $repo
}

# The secrets revision rev's tree records, null without one.
def secrets-recorded [repo: path, rev: string]: nothing -> any {
    ^git -C $repo ls-tree $rev $SECRETS_GITLINK | parse --regex '^\S+ commit (?<sha>[0-9a-f]+)' | get --optional 0.sha
}

def secrets-follow [repo: path]: nothing -> nothing {
    let secrets = $repo | path join configs secrets
    if not (secrets-wanted) or not ($secrets | path join .git | path exists) { return }
    secrets-follow-recorded $repo $secrets
    secrets-keys-chmod $secrets
}

def secrets-follow-recorded [repo: path, secrets: path]: nothing -> nothing {
    let recorded = secrets-recorded $repo HEAD
    let current = ^git -C $secrets rev-parse HEAD | str trim
    if $recorded == null or $recorded == $current { return }
    if not (succeeds git -C $secrets cat-file -e $"($recorded)^{commit}") {
        try { ^git -C $secrets fetch --quiet origin } catch { error make {msg: "secrets: fetch failed, the pulled generation names a revision this checkout lacks"} }
    }
    if (succeeds git -C $secrets merge-base --is-ancestor $recorded $current) { return }
    if not (succeeds git -C $secrets merge-base --is-ancestor $current $recorded) {
        if (^git -C $secrets status --porcelain | str trim | is-not-empty) {
            error make {msg: $"secrets: ($current) and the pulled ($recorded) diverged and ($secrets) has uncommitted edits"}
        }
        if not (succeeds git -C $secrets rebase --quiet $recorded) {
            ^git -C $secrets rebase --abort
            error make {msg: $"secrets: ($current) and the pulled ($recorded) changed the same file, merge them in ($secrets)"}
        }
        return
    }
    try { ^git -C $secrets checkout --quiet $recorded } catch {
        error make {msg: $"secrets: local edits conflict with the pulled revision ($recorded), commit or move them in ($secrets)"}
    }
}

def fingerprint [repo: path]: nothing -> string {
    bootstrap-const $repo SIGNING_KEY_FINGERPRINT $FINGERPRINT_VALUE
}

# Whether gpg holds the secret key bootstrap.sh's SIGNING_KEY_FINGERPRINT names.
export def sync-can-sign [repo: path]: nothing -> bool {
    succeeds gpg --batch --list-secret-keys (fingerprint $repo)
}

# The changed files of the secrets checkout a commit would store unencrypted: all but keys/ (git-crypt's), state/
# (plaintext app state), its own .git-crypt and .gitattributes, and the files inside a module dir (modules: the top dirs
# holding a mod.nu).
export def secrets-stray [changed: list<string>, modules: list<string>]: nothing -> list<string> {
    $changed | where {|f|
        let parts = $f | path split
        let module = ($parts | length) > 1 and $parts.0 in $modules
        $parts.0 not-in [keys state .git-crypt] and $f != .gitattributes and not $module
    }
}

# The files a commit of the secrets checkout would add or change: staged, unstaged and untracked, deletions left out.
export def secrets-changed [secrets: path]: nothing -> list<string> {
    ^git -C $secrets status --porcelain -z --untracked-files=all --no-renames | split row (char nul)
    | where ($it | str length) > 3 | each { str substring 3.. }
    | where {|f| $secrets | path join $f | path exists }
}

# The staged files under keys/ whose blob git-crypt did not encrypt: with a .gitattributes that lost its filter line
# the commit would store them in clear.
export def secrets-staged-clear [secrets: path]: nothing -> list<string> {
    ^git -C $secrets diff --cached --name-only -z --no-renames --diff-filter=d -- keys | split row (char nul)
    | where {|f| $f != "" and not (^git -C $secrets cat-file blob $":($f)" | into binary | secret-bytes-locked) }
}

def secrets-plaintext-guard [secrets: path]: nothing -> nothing {
    let changed = secrets-changed $secrets
    let modules = $changed | each { path split | first } | uniq | where {|d| $secrets | path join $d mod.nu | path exists }
    let stray = secrets-stray $changed $modules
    if ($stray | is-not-empty) {
        error make {msg: $"secrets: ($stray | str join ' ') would be committed unencrypted: move it under configs/secrets/keys/ (a credential) or state/"}
    }
}

def secrets-commit [secrets: path]: nothing -> nothing {
    if (^git -C $secrets status --porcelain | str trim | is-empty) { return }
    secrets-plaintext-guard $secrets
    ^git -C $secrets add -A
    let clear = secrets-staged-clear $secrets
    if ($clear | is-not-empty) {
        ^git -C $secrets reset --quiet
        error make {msg: $"secrets: ($clear | str join ' ') would be committed in clear, nothing committed: check ($secrets)/.gitattributes and git -C ($secrets) crypt status"}
    }
    ^git -C $secrets commit -m "chore(sync): back up live app state"
}

# The secrets revision origin's head names, checked to be a signed generation each time it is read, and fetched into
# the secrets checkout. Secrets commits are unsigned and the module dirs there reach root, so this is the only commit
# of the secrets origin the checkout ever moves onto: never that origin's own head.
def secrets-named [repo: path, secrets: path]: nothing -> string {
    origin-verified $repo
    let named = secrets-recorded $repo $"origin/($BRANCH)"
    if $named == null { error make {msg: $"secrets: origin/($BRANCH) records no ($SECRETS_GITLINK)"} }
    let fetched = ^git -C $secrets fetch --quiet origin | complete
    if not (succeeds git -C $secrets cat-file -e $"($named)^{commit}") {
        error make {msg: $"secrets: origin's generation names ($named), which the secrets origin does not hold: (error-brief $fetched.stderr)"}
    }
    $named
}

# git's own fatal/error line: git-lfs prints a harmless locking-api warning first, which hid the cause; a refusal by
# the remote (push protection, a hook, a size limit) says why only in its remote: and [remote rejected] lines
def push-error [stderr: string]: nothing -> string {
    let why = $stderr | lines | where $it =~ '^(fatal|error|remote): |\[remote rejected\]' | str join " " | str trim
    if $why == "" { error-brief $stderr } else { $why }
}

# Pushes the secrets checkout; a rejected push rebases it onto the revision origin's signed generation names (another
# machine's sync) and fails when the secrets origin holds more than that. A checkout with no commit of its own past that
# revision only fast-forwards to it: it has nothing to push, and adopts nothing unnamed.
export def secrets-push [repo: path, secrets: path]: nothing -> nothing {
    mut tries = 0
    mut push = ^git -C $secrets push origin $"HEAD:($BRANCH)" | complete
    while $push.exit_code != 0 {
        if not ($push.stderr | str contains $PUSH_REJECTED) { error make {msg: $"secrets: push failed: (push-error $push.stderr)"} }
        $tries += 1
        if $tries > $PUSH_TRIES { error make {msg: $"secrets: push still rejected after ($PUSH_TRIES) rebases"} }
        origin-fetch $repo
        let named = secrets-named $repo $secrets
        if (succeeds git -C $secrets merge-base --is-ancestor HEAD $named) {
            ^git -C $secrets merge --ff-only --quiet $named
            return
        }
        if (succeeds git -C $secrets merge-base --is-ancestor $named HEAD) {
            error make {msg: $"secrets origin holds commits no signed generation names, nothing adopted: finish the dot sync that pushed them, or inspect git -C ($secrets) log origin/($BRANCH)"}
        }
        if not (succeeds git -C $secrets rebase $named) {
            ^git -C $secrets rebase --abort
            error make {msg: $"secrets: this machine's backup and origin's ($named) changed the same file, resolve it in ($secrets)"}
        }
        $push = ^git -C $secrets push origin $"HEAD:($BRANCH)" | complete
    }
}

# Fast-forwards the secrets checkout to the revision origin's signed generation names; origin-fetch ran before.
export def secrets-fast-forward [repo: path, secrets: path]: nothing -> nothing {
    let named = secrets-named $repo $secrets
    if not (succeeds git -C $secrets merge --ff-only --quiet $named) {
        error make {msg: $"secrets: ($secrets) and origin's ($named) diverged after pushing, nothing committed; reconcile it, then dot sync again"}
    }
}

# Commits secrets, then the signed generation, and pushes both; --no-verify skips dot test check and gitleaks.
export def sync-commit [repo: path, --no-verify]: nothing -> nothing {
    sync-branch-check $repo
    let fpr = fingerprint $repo
    if not (sync-can-sign $repo) {
        error make {msg: $"no secret key ($fpr) to sign with, so no generation from this machine: dot secrets unlock && dot apply --user imports it"}
    }

    ^nu --no-config-file ($repo | path join scripts lib internal.nu) backup
    luks-header-sync $repo
    let secrets = $repo | path join configs secrets
    if (secrets-wanted) and (secret-is-plaintext ($repo | path join $OWNER_WITNESS)) {
        secrets-commit $secrets
        secrets-push $repo $secrets
    }

    sync-catch-up $repo
    generated-refresh $repo
    # not behind --no-verify: `git add .` would put whatever a tool left in the checkout into a signed generation
    let stray = lint-stray $repo
    if ($stray | is-not-empty) { error make {msg: $"nothing committed:\n($stray | str join "\n")"} }
    ^git -C $repo add .
    mut committed = false
    if (succeeds git -C $repo diff --cached --quiet) {
        log-info "sync: nothing changed, no new generation"
    } else {
        let broken = ^git -C $repo ls-files -z '*.sh' | split row (char nul) | where $it != "" | par-each {|f| if not (succeeds bash -n ($repo | path join $f)) { $f } } | compact
        if ($broken | is-not-empty) { error make {msg: $"does not parse, nothing committed: ($broken | str join ' ')"} }
        if not $no_verify {
            try { ^nu --no-config-file ($repo | path join scripts dot.nu) test check } catch { error make {msg: "dot test check found a problem, nothing committed (dot sync --no-verify overrides)"} }
            try { do { cd $repo; ^gitleaks git --staged --redact --no-banner } } catch { error make {msg: "gitleaks found a secret in the staged tree, nothing committed (dot sync --no-verify overrides)"} }
        }
        generation-commit $repo $fpr
        $committed = true
    }
    mut tries = 0
    mut push = ^git -C $repo push --no-recurse-submodules | complete
    while $push.exit_code != 0 {
        $tries += 1
        if $tries > $PUSH_TRIES { error make {msg: $"push still rejected after ($PUSH_TRIES) retries"} }
        if not ($push.stderr | str contains $PUSH_REJECTED) { error make {msg: $"push failed, nothing rewound: (push-error $push.stderr)"} }
        if $committed { ^git -C $repo reset --soft HEAD~1 }
        origin-fetch $repo
        # move the secrets submodule first, so the stash carries no gitlink change
        if (secrets-wanted) and ($secrets | path join .git | path exists) { secrets-fast-forward $repo $secrets }
        ^git -C $repo stash push --quiet --include-untracked
        try { origin-merge $repo } catch {|e|
            error make {msg: $"($e.msg)\nthis machine's changes are stashed, not lost: git -C ($repo) stash pop, then dot sync again"}
        }
        if not (succeeds git -C $repo stash pop --quiet) {
            error make {msg: $"the stashed changes conflict with origin's generation; they stay in `git -C ($repo) stash list`, resolve them, then dot sync again"}
        }
        generated-refresh $repo
        ^git -C $repo add .
        if $committed { generation-commit $repo $fpr }
        $push = ^git -C $repo push --no-recurse-submodules | complete
    }
}

# dot internal gen on the tree about to be staged (after a catch-up merged origin's), so no generation carries a stale
# generated file; lint's gen --check still catches one between syncs.
def generated-refresh [repo: path]: nothing -> nothing {
    let internal = $repo | path join scripts lib internal.nu
    let run = ^nu --no-config-file $internal gen | complete
    if $run.exit_code != 0 { error make {msg: $"dot internal gen failed, nothing committed: ($run.stdout + $run.stderr | str trim)"} }
    # gen leaves a module that does not parse out of mirror/packages.txt without failing; only --check refuses it
    let check = ^nu --no-config-file $internal gen --check | complete
    if $check.exit_code != 0 { error make {msg: $"dot internal gen --check failed, nothing committed: ($check.stdout + $check.stderr | str trim)"} }
}

def generation-commit [repo: path, fpr: string]: nothing -> nothing {
    let last = ^git -C $repo log --format=%s | parse --regex '(?m)^Generation: (?<n>\d+)' | get --optional 0.n | default "0" | into int
    ^git -C $repo -c gpg.format=openpgp commit $"-S($fpr)" -m $"Generation: ($last + 1)"
}

def luks-header-path [repo: path]: nothing -> path {
    $repo | path join configs secrets keys $"luks-headers/(open --raw /etc/hostname | str trim).img"
}

def luks-root []: nothing -> bool {
    let source = ^findmnt -n -o SOURCE / | str trim | split row "[" | first
    if not ($source | str starts-with "/dev/mapper/") { return false }
    (^lsblk -n -o TYPE $source | str trim) == "crypt"
}

def luks-header-checked-stamp []: nothing -> path {
    state-dir | path join $"luks-header-checked-(sys host | get hostname)"
}

# The stamp lives outside git: an unchanged header makes no commit to date it by.
def luks-header-due [header: path]: nothing -> bool {
    if not ($header | path exists) { return true }
    let stamp = luks-header-checked-stamp
    if not ($stamp | path exists) { return true }
    let touched = open --raw $stamp | str trim | into int | $in * 1sec + 1970-01-01
    (date now) - $touched > ($LUKS_HEADER_MAX_AGE_DAYS * 1day)
}

# Root re-backs up a missing or stale LUKS header; skipped off LUKS or while secrets are locked.
export def luks-header-sync [repo: path]: nothing -> nothing {
    if not (luks-root) { return }
    if $env.DOT_SYSTEM? == "skip" { return }
    if not (secret-is-plaintext ($repo | path join $OWNER_WITNESS)) { return }
    try {
        if not (luks-header-due (luks-header-path $repo)) { return }
        ^nu --no-config-file ($repo | path join configs base boot luks scripts header-backup.nu)
        let stamp = luks-header-checked-stamp
        mkdir ($stamp | path dirname)
        (date now | format date "%s") | save --force $stamp
    } catch {|e| log-warn $"luks header backup: ($e.msg)" }
}

def origin-fetch [repo: path]: nothing -> nothing {
    ^git -C $repo fetch --quiet --no-recurse-submodules origin
    origin-verified $repo
}

def sync-catch-up [repo: path]: nothing -> nothing {
    origin-fetch $repo
    origin-merge $repo
}

def origin-merge [repo: path]: nothing -> nothing {
    if not (succeeds git -C $repo merge --ff-only --autostash $"origin/($BRANCH)") {
        error make {msg: $"($BRANCH) diverged from origin while syncing, nothing committed: git -C ($repo) pull --rebase"}
    }
    # a conflicting autostash pop still exits 0 and leaves markers that `git add .` would commit
    let conflicted = ^git -C $repo diff --name-only --diff-filter=U | lines
    if ($conflicted | is-not-empty) {
        error make {msg: $"origin's generation and this machine's changes conflict in ($conflicted | str join ', '), nothing committed; resolve them in ($repo) \(the stash is kept\), then dot sync again"}
    }
}
