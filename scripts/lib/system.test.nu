#!/usr/bin/env -S nu --no-config-file
# A packed and unpacked checkout keeps configs/secrets root-only, and its digest matches the checkout's; a module root
# never runs a hook of ships only its .nu files, so the copy stays current when its state changes after the pack; one
# with a root verb in any of its .nu files ships whole, as does one whose detect a root-run module reads. An archive
# whose entry does not parse never replaces the copy; the digest of the secrets handed to root is the one root derives
# from what it unpacked. The secrets root may be handed are what the modules' meta.secrets and the platform's wireguard
# configs name, relative to configs/secrets/keys/ ({host} this machine's name), and nothing that leaves keys/ by an
# absolute path or a `..`.
use system.nu [system-pack system-unpack system-files system-archive system-secrets system-secrets-digest entry-parses secrets-digest SECRETS_PREFIX SECRETS_DIGEST ENTRY]
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

    # root records the digest of the secrets tar it extracted; the user derives the same from the checkout
    let keys = $secrets | path join keys
    mkdir ($keys | path join wg)
    "key-a\n" | save ($keys | path join wg lab.conf)
    "export const meta = {secrets: [token]}\nexport def system [cfg: record] { [] }\n" | save --force ($reader | path join mod.nu)
    "token-b\n" | save ($keys | path join token)
    let handed = $work | path join handed
    mkdir $handed
    system-archive $checkout "wg/lab.conf" | ^tar -x -C $handed -f - secrets.tar
    let extracted = $work | path join extracted
    mkdir $extracted
    ^tar -x -C $extracted -f ($handed | path join secrets.tar)
    let held = ^find $extracted -type f -printf '%P\n' | lines
    assert equal ($held | sort) [token wg/lab.conf] $"the secrets tar holds ($held | to nuon)"
    assert equal (secrets-digest $extracted $held) (system-secrets-digest $checkout "wg/lab.conf") "root's digest of the handed secrets differs from the checkout's"
    "token-c\n" | save --force ($keys | path join token)
    assert ((secrets-digest $extracted $held) != (system-secrets-digest $checkout "wg/lab.conf")) "a changed secret keeps the digest"

    # an entry that does not parse stays out: the copy that could still unpack a fixed one is kept
    assert (entry-parses $copy) "the unpacked copy's entry does not parse"
    let source = open --raw ($copy | path join .source)
    "def main [] { let broken = \n" | save --force ($checkout | path join $ENTRY)
    let refused = try { system-pack $checkout $copy | system-unpack $copy $SHA; "" } catch {|e| $e.msg }
    assert ($refused | str contains "does not parse") $"an archive with a broken entry was unpacked: ($refused)"
    assert (entry-parses $copy) "the copy took the broken entry"
    assert equal (open --raw ($copy | path join .source)) $source "the refused archive changed the copy"
    assert not ($"($copy).new" | path exists) "the refused archive was left beside the copy"
    "use absent-module.nu [x]\n" | save --force ($checkout | path join $ENTRY)
    assert ((try { system-pack $checkout $copy | system-unpack $copy $SHA; "" } catch {|e| $e.msg }) | str contains "does not parse") "an entry with a missing import was unpacked"
}

def secrets-cases [repo: path]: nothing -> nothing {
    let host = sys host | get hostname
    let declare = {|id: string, secrets: list<string>|
        mkdir ($repo | path join configs $id)
        $"export const meta = {secrets: ($secrets | to nuon)}\nexport def system [cfg: record] { [] }\n" | save --force ($repo | path join configs $id mod.nu)
    }
    let refused = {|wireguard: any| try { system-secrets $repo $wireguard | ignore; "" } catch {|e| $e.msg } }
    do $declare base/ssh ["ssh-host/{host}/ssh_host_ed25519_key" "shared/token"]
    do $declare base/plain []
    do $declare other/again ["shared/token"]
    let got = system-secrets $repo ["wireguard/pc.conf" ""] | sort
    assert equal $got ["shared/token" $"ssh-host/($host)/ssh_host_ed25519_key" "wireguard/pc.conf"] $"declared secrets: ($got | to nuon)"
    assert equal (system-secrets $repo null | sort) ["shared/token" $"ssh-host/($host)/ssh_host_ed25519_key"] "no wireguard config"
    for outside in ["/etc/shadow" "../state/app/token" "wireguard/../../../.git/config"] {
        assert (do $refused $outside | str contains $"secrets outside keys/: ($outside)") $"wireguard ($outside) was not refused"
    }
    do $declare base/escapes ["ssh-host/{host}/../../../yubikey/u2f_keys"]
    assert (do $refused null | str contains "secrets outside keys/") "a module's meta.secrets left keys/"
}

def main [] {
    let work = mktemp --directory --tmpdir system-test.XXXXXX
    $env.XDG_CACHE_HOME = $work | path join cache
    # the user's git config (commit.gpgsign, a template dir) stays out of the scratch repos
    $env.GIT_CONFIG_GLOBAL = "/dev/null"
    $env.GIT_CONFIG_SYSTEM = "/dev/null"
    try { check $work; secrets-cases ($work | path join declared) } catch {|e| rm --recursive --force $work; error make $e }
    rm --recursive --force $work
}
