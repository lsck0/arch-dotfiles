# The git half of dot sync: pull with the secrets submodule following, then the signed `Generation: <n>` commit
# and push, retried on top when another machine pushed first.

use log.nu *
use secrets.nu [secret-is-plaintext secrets-wanted]

const BRANCH = "master"
const PUSH_TRIES = 3
const SIGNING_KEY_FILE = "configs/core/gnupg/luca-sandrock.pub.asc"
const FINGERPRINT_LINE = '(?m)^SIGNING_KEY_FINGERPRINT=(?<fpr>[0-9A-F]{40})$'
const LUKS_HEADER_MAX_AGE_DAYS = 90

# Fails unless HEAD is on master: a detached HEAD would commit off it and the push would fail.
export def sync-branch-check [repo: path]: nothing -> nothing {
    if (try { ^git -C $repo symbolic-ref -q --short HEAD | str trim } catch { "" }) != $BRANCH {
        error make {msg: $"HEAD is not on ($BRANCH), go back with: git switch ($BRANCH)"}
    }
}

# The fetched origin head must carry the owner's signature before anything merges it: the next system apply runs it as
# root. Checked against the key in the repo with a throwaway keyring, so a machine without the owner's gpg setup
# (a server, a custom profile) checks it too.
def origin-verified [repo: path]: nothing -> nothing {
    let rev = $"origin/($BRANCH)"
    let gnupg = mktemp --directory
    let status = with-env {GNUPGHOME: $gnupg} {
        ^gpg --batch --quiet --import ($repo | path join $SIGNING_KEY_FILE)
        ^git -C $repo verify-commit --raw $rev | complete
    }
    rm --recursive --force $gnupg
    let signer = $status.stderr | lines | where ($it | str contains "VALIDSIG") | get --optional 0 | default "" | split row " " | last
    if $status.exit_code != 0 or $signer != (fingerprint $repo) {
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

def secrets-follow [repo: path]: nothing -> nothing {
    let secrets = $repo | path join configs secrets
    if not (secrets-wanted) or not ($secrets | path join .git | path exists) { return }
    let recorded = ^git -C $repo ls-tree HEAD configs/secrets | parse --regex '^\S+ commit (?<sha>[0-9a-f]+)' | get --optional 0.sha
    let current = ^git -C $secrets rev-parse HEAD | str trim
    if $recorded == null or $recorded == $current { return }
    if (^git -C $secrets cat-file -e $"($recorded)^{commit}" | complete).exit_code != 0 {
        try { ^git -C $secrets fetch --quiet origin } catch { error make {msg: "secrets: fetch failed, the pulled generation names a revision this checkout lacks"} }
    }
    if (^git -C $secrets merge-base --is-ancestor $recorded $current | complete).exit_code == 0 { return }
    if (^git -C $secrets merge-base --is-ancestor $current $recorded | complete).exit_code != 0 {
        if (^git -C $secrets status --porcelain | str trim | is-not-empty) {
            error make {msg: $"secrets: ($current) and the pulled ($recorded) diverged and ($secrets) has uncommitted edits"}
        }
        if (^git -C $secrets rebase --quiet $recorded | complete).exit_code != 0 {
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
    let fpr = open --raw ($repo | path join bootstrap.sh) | parse --regex $FINGERPRINT_LINE | get fpr
    if ($fpr | length) != 1 { error make {msg: "bootstrap.sh has no single SIGNING_KEY_FINGERPRINT=<40 hex>"} }
    $fpr.0
}

# Whether gpg holds the secret key bootstrap.sh's SIGNING_KEY_FINGERPRINT names.
export def sync-can-sign [repo: path]: nothing -> bool {
    (^gpg --batch --list-secret-keys (fingerprint $repo) | complete).exit_code == 0
}

def secrets-plaintext-guard [secrets: path]: nothing -> nothing {
    let stray = ^git -C $secrets ls-files -z --others --modified --exclude-standard | split row (char nul)
        | where {|f| $f != "" and ($secrets | path join $f | path exists) }
        | where {|f|
            let parts = $f | path split
            let module = ($parts | length) > 1 and ($secrets | path join $parts.0 mod.nu | path exists)
            $parts.0 not-in [keys state .git-crypt] and $f != .gitattributes and not $module
        }
    if ($stray | is-not-empty) {
        error make {msg: $"secrets: ($stray | str join ' ') would be committed unencrypted: move it under configs/secrets/keys/ (a credential) or state/"}
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
    if (secrets-wanted) and (secret-is-plaintext ($secrets | path join keys pgp_privatekey.asc)) {
        if (^git -C $secrets status --porcelain | str trim | is-not-empty) {
            secrets-plaintext-guard $secrets
            ^git -C $secrets add -A
            ^git -C $secrets commit -m "chore(sync): back up live app state"
        }
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

    sync-catch-up $repo
    ^git -C $repo add .
    mut committed = false
    if (^git -C $repo diff --cached --quiet | complete).exit_code == 0 {
        log-info "sync: nothing changed, no new generation"
    } else {
        let broken = ^git -C $repo ls-files -z '*.sh' | split row (char nul) | where $it != "" | par-each {|f| if (^bash -n ($repo | path join $f) | complete).exit_code != 0 { $f } } | compact
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
        if not ($push.stderr | str contains "non-fast-forward") and not ($push.stderr | str contains "fetch first") and not ($push.stderr | str contains "rejected") {
            error make {msg: $"push failed, nothing rewound: (error-brief $push.stderr)"}
        }
        if $committed { ^git -C $repo reset --soft HEAD~1 }
        ^git -C $repo stash push --quiet --include-untracked
        sync-catch-up $repo
        ^git -C $repo stash pop --quiet
        ^git -C $repo add .
        if $committed { generation-commit $repo $fpr }
        $push = ^git -C $repo push --no-recurse-submodules | complete
    }
}

def generation-commit [repo: path, fpr: string]: nothing -> nothing {
    let last = ^git -C $repo log --format=%s | parse --regex '(?m)^Generation: (?<n>\d+)' | get --optional 0.n | default "0" | into int
    ^git -C $repo -c gpg.format=openpgp commit $"-S($fpr)" -m $"Generation: ($last + 1)"
}

def luks-header-path [repo: path]: nothing -> path {
    $repo | path join configs secrets keys $"luks-header-(open --raw /etc/hostname | str trim).img"
}

def luks-root []: nothing -> bool {
    let source = ^findmnt -n -o SOURCE / | str trim | split row "[" | first
    if not ($source | str starts-with "/dev/mapper/") { return false }
    (^lsblk -n -o TYPE $source | str trim) == "crypt"
}

def luks-header-checked-stamp []: nothing -> path {
    $nu.home-dir | path join .local state dotfiles $"luks-header-checked-(open --raw /etc/hostname | str trim)"
}

# Due when missing or last backed up over LUKS_HEADER_MAX_AGE_DAYS ago; the stamp lives outside git, since an
# unchanged header makes no new commit to date it by.
def luks-header-due [header: path]: nothing -> bool {
    if not ($header | path exists) { return true }
    let stamp = luks-header-checked-stamp
    if not ($stamp | path exists) { return true }
    let touched = open --raw $stamp | str trim | into int | $in * 1sec + 1970-01-01
    (date now) - $touched > ($LUKS_HEADER_MAX_AGE_DAYS * 1day)
}

# Keeps the LUKS header backup current: missing or stale, root re-backs it up (base/boot/luks/header-backup.nu)
# so the secrets commit right after carries it. Silently skipped off a LUKS root or while secrets are locked.
export def luks-header-sync [repo: path]: nothing -> nothing {
    if not (luks-root) { return }
    if $env.DOT_SYSTEM? == "skip" { return }
    let secrets = $repo | path join configs secrets
    if not (secret-is-plaintext ($secrets | path join keys pgp_privatekey.asc)) { return }
    try {
        if not (luks-header-due (luks-header-path $repo)) { return }
        ^nu --no-config-file ($repo | path join configs base boot luks header-backup.nu)
        let stamp = luks-header-checked-stamp
        mkdir ($stamp | path dirname)
        (date now | format date "%s") | save --force $stamp
    } catch {|e| log-warn $"luks header backup: ($e.msg)" }
}

def sync-catch-up [repo: path]: nothing -> nothing {
    ^git -C $repo fetch --quiet --no-recurse-submodules origin
    origin-verified $repo
    if (^git -C $repo merge --ff-only --autostash $"origin/($BRANCH)" | complete).exit_code != 0 {
        error make {msg: $"($BRANCH) diverged from origin while syncing, nothing committed: git -C ($repo) pull --rebase"}
    }
}
