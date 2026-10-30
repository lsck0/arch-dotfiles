#!/usr/bin/env -S nu --no-config-file
# A packed and unpacked checkout keeps configs/secrets root-only, and its digest matches the checkout's.
use system.nu [system-pack system-unpack system-files secrets-digest SECRETS_PREFIX SECRETS_DIGEST ENTRY]

const SHA = "0123456789abcdef0123456789abcdef01234567"

def fail [msg: string] { error make {msg: $"system.test: ($msg)"} }

def git-init [dir: path]: nothing -> nothing {
    let git = [-C $dir -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@localhost]
    ^git ...$git init --quiet
    ^git ...$git add --all --no-warn-embedded-repo
    ^git ...$git commit --quiet --message test
}

def check [work: path]: nothing -> nothing {
    let checkout = $work | path join checkout
    let copy = $work | path join copy
    let secrets = $checkout | path join $SECRETS_PREFIX
    mkdir ($checkout | path join ($ENTRY | path dirname)) ($secrets | path join shell)
    "" | save ($checkout | path join $ENTRY)
    "" | save ($secrets | path join shell mod.nu)
    "alias x=y\n" | save ($secrets | path join shell aliases.zsh)
    git-init $secrets
    git-init $checkout

    system-pack $checkout $copy | system-unpack $copy $SHA
    let modes = ^find ($copy | path join $SECRETS_PREFIX) -printf '%m %P\n' | lines
    let open = $modes | where {|m| ($m | str substring 1..2) != "00" }
    if ($open | is-not-empty) { fail $"($SECRETS_PREFIX) readable by others: ($open | str join ', ')" }
    if (^stat -c '%a' $copy | str trim) != "755" { fail "the copy is not 755" }

    let private = system-files $checkout "--cached" | where ($it | str starts-with $SECRETS_PREFIX)
    if ($private | length) != 2 { fail $"($private | length) secrets files packed, wants 2" }
    let digest = open --raw ($copy | path join $SECRETS_DIGEST) | str trim
    if $digest != (secrets-digest $checkout $private) { fail "the copy's digest differs from the checkout's" }
}

def main [] {
    let work = mktemp --directory --tmpdir system-test.XXXXXX
    try { check $work } catch {|e| rm --recursive --force $work; error make {msg: $e.msg} }
    rm --recursive --force $work
}
