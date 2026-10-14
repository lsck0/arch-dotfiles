use log.nu *
use secrets.nu [secret-is-plaintext]

const BRANCH = "master"
const FINGERPRINT_LINE = '(?m)^SIGNING_KEY_FINGERPRINT=(?<fpr>[0-9A-F]{40})$'

export def sync-run [repo: path, --no-verify]: nothing -> nothing {
    # a rollback leaves a detached HEAD at an old generation; a commit there is off master and the push fails
    if (try { ^git -C $repo symbolic-ref -q --short HEAD | str trim } catch { "" }) != $BRANCH {
        error make {msg: $"HEAD is not on ($BRANCH), go back with: git switch ($BRANCH)"}
    }
    # the key bootstrap.sh trusts, so every pushed generation is one a fresh install accepts
    let fpr = open --raw ($repo | path join bootstrap.sh) | parse --regex $FINGERPRINT_LINE | get fpr
    if ($fpr | length) != 1 { error make {msg: "bootstrap.sh has no single SIGNING_KEY_FINGERPRINT=<40 hex>"} }
    let fpr = $fpr.0
    if (^gpg --batch --list-secret-keys $fpr | complete).exit_code != 0 {
        error make {msg: $"no secret key ($fpr) to sign with, import it: dot secrets unlock && dot link"}
    }
    let last = ^git -C $repo log --format=%s | parse --regex '(?m)^Generation: (?<n>\d+)' | get --optional 0.n | default "0" | into int

    ^nu --no-config-file ($repo | path join scripts dot.nu) backup
    # secrets first, so the generation commit records its new revision
    let secrets = $repo | path join secrets
    if (secret-is-plaintext ($secrets | path join pgp_privatekey.asc)) {
        if (^git -C $secrets status --porcelain | str trim | is-not-empty) {
            ^git -C $secrets add -A
            ^git -C $secrets commit -m "chore(sync): back up live app state"
        }
        # submodule update leaves a detached HEAD, so push it to the branch explicitly
        ^git -C $secrets push origin $"HEAD:($BRANCH)"
    }

    ^git -C $repo add .
    # bootstrap.sh and the lsck0 builder consume master directly: a script that does not parse never becomes a generation
    let broken = ^git -C $repo ls-files -z '*.sh' | split row (char nul) | where $it != "" | par-each {|f| if (^bash -n ($repo | path join $f) | complete).exit_code != 0 { $f } } | compact
    if ($broken | is-not-empty) { error make {msg: $"does not parse, nothing committed: ($broken | str join ' ')"} }
    # master is public: a credential in any tracked file must never get there; secrets/ is encrypted and allowlisted
    if not $no_verify {
        try { ^nu --no-config-file ($repo | path join scripts dot.nu) test check } catch { error make {msg: "dot test check found a problem, nothing committed (dot sync --no-verify overrides)"} }
        try { do { cd $repo; ^gitleaks git --staged --redact --no-banner } } catch { error make {msg: "gitleaks found a secret in the staged tree, nothing committed (dot sync --no-verify overrides)"} }
    }
    ^git -C $repo -c gpg.format=openpgp commit $"-S($fpr)" -m $"Generation: ($last + 1)"
    # secrets is pushed above; qmk_firmware is read-only upstream, so no recursion
    ^git -C $repo push --no-recurse-submodules
}
