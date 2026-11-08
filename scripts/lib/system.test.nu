#!/usr/bin/env -S nu --no-config-file
# A packed and unpacked checkout keeps configs/secrets root-only, and its digest matches the checkout's; a module root
# never runs a hook of ships only its .nu files, so the copy stays current when its state changes after the pack; one
# with a root verb in any of its .nu files ships whole, as does one whose detect a root-run module reads.
use system.nu [system-pack system-unpack system-files secrets-digest SECRETS_PREFIX SECRETS_DIGEST ENTRY]
use std/assert

const SHA = "0123456789abcdef0123456789abcdef01234567"

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
    "export def system [cfg: record] { [] }\n" | save ($secrets | path join shell mod.nu)
    "alias x=y\n" | save ($secrets | path join shell aliases.zsh)
    let app = $checkout | path join configs group app
    mkdir $app
    "export def link [cfg: record] { [] }\n" | save ($app | path join mod.nu)
    "{}\n" | save ($app | path join state.json)
    let helped = $checkout | path join configs group helped
    mkdir $helped
    "export use root.nu *\n" | save ($helped | path join mod.nu)
    "export def packages [cfg: record] { [] }\n" | save ($helped | path join root.nu)
    "x\n" | save ($helped | path join unit.conf)
    # a detect root needs only when a root-run module reads it: probed is, sensed is not
    for m in [sensed probed] {
        mkdir ($checkout | path join configs group $m)
        "export def detect [cfg: record] { {} }\nexport def link [cfg: record] { [] }\n" | save ($checkout | path join configs group $m mod.nu)
        "{}\n" | save ($checkout | path join configs group $m state.json)
    }
    let reader = $checkout | path join configs group reader
    mkdir $reader
    "export const meta = {reads: [group/probed]}\nexport def system [cfg: record] { [] }\n" | save ($reader | path join mod.nu)
    git-init $secrets
    git-init $checkout

    system-pack $checkout $copy | system-unpack $copy $SHA
    let modes = ^find ($copy | path join $SECRETS_PREFIX) -printf '%m %P\n' | lines
    let open = $modes | where {|m| ($m | str substring 1..2) != "00" }
    assert ($open | is-empty) $"($SECRETS_PREFIX) readable by others: ($open | str join ', ')"
    assert equal (^stat -c '%a' $copy | str trim) "755" "the copy is not 755"

    let private = system-files $checkout "--cached" | where ($it | str starts-with $SECRETS_PREFIX)
    assert equal ($private | length) 2 $"($private | length) secrets files packed, wants 2"
    let digest = open --raw ($copy | path join $SECRETS_DIGEST) | str trim
    assert equal $digest (secrets-digest $checkout $private) "the copy's digest differs from the checkout's"

    let packed = system-files $checkout "--cached"
    assert ("configs/group/app/mod.nu" in $packed) "a user-only module's mod.nu is not packed"
    assert ("configs/group/app/state.json" not-in $packed) "a user-only module's app state is packed"
    assert not ($copy | path join configs group app state.json | path exists) "the copy holds a user-only module's app state"
    assert ("configs/group/helped/unit.conf" in $packed) "a module whose root verb sits in a helper file is not packed whole"
    assert ("configs/group/sensed/state.json" not-in $packed) "a detect no root-run module reads ships its module whole"
    assert ("configs/group/probed/state.json" in $packed) "a detect a root-run module reads does not ship its module whole"

    # a backup writing a user-only module's state after the pack leaves the copy current, as dot status compares it
    "{changed: true}\n" | save --force ($checkout | path join configs group sensed state.json)
    let ours = system-files $checkout "--cached" | where not ($it | str starts-with $SECRETS_PREFIX) | sort
    let theirs = cd $copy | ^find . -path $"./($SECRETS_PREFIX | str trim --right --char '/')" -prune -o -type f ! -name .source ! -name $SECRETS_DIGEST -printf '%P\n' | lines | sort
    assert equal $theirs $ours "the copy holds other files than the checkout packs"
    let differing = $ours | where {|f| (open --raw ($checkout | path join $f) | hash sha256) != (open --raw ($copy | path join $f) | hash sha256) }
    assert equal $differing [] "the copy differs from the checkout after a user-only module's backup"
}

def main [] {
    let work = mktemp --directory --tmpdir system-test.XXXXXX
    $env.XDG_CACHE_HOME = $work | path join cache
    try { check $work } catch {|e| rm --recursive --force $work; error make $e }
    rm --recursive --force $work
}
