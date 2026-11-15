#!/usr/bin/env -S nu --no-config-file
# dot status's luks and crash checks: a LUKS root no token unlocks is a note naming the enrol command, a token the
# cmdline asks for and the boot missed is one too, and a crash record stays a note until it is gone. A declared
# package that is not installed fails the packages check, unless the mirror's last build predates its first ask.
use doctor.nu [luks-reports crash-reports packages-reports]
use std/assert

const UUID = "39244fe4-3a83-414e-aa5e-f1a17f10057d"

def luks-cases []: nothing -> nothing {
    let root = $"rd.luks.name=($UUID)=root root=/dev/mapper/root rw"
    let cases = [
        [name cmdline missing wants];
        ["no luks root" "root=/dev/nvme0n1p2 rw" [] []]
        ["no token asked" $"($root) rd.luks.options=tpm2-measure-pcr=yes,tries=0" [] [$"--fido2-device=auto /dev/disk/by-uuid/($UUID)"]]
        ["no options at all" $root [] ["passphrase alone"]]
        ["fido2 asked and found" $"($root) rd.luks.options=fido2-device=auto,tries=0" [] []]
        ["tpm2 asked and missed" $"($root) rd.luks.options=tpm2-device=auto,tries=0" [TPM2] ["no TPM2 token"]]
        ["a miss nobody asked for" $"($root) rd.luks.options=fido2-device=auto" [TPM2] []]
    ]
    for c in $cases {
        let got = luks-reports $c.cmdline $c.missing
        assert equal ($got | length) ($c.wants | length) $"luks ($c.name): ($got | to nuon)"
        for pair in ($got | zip $c.wants) {
            assert ($pair.0.level == "note" and ($pair.0.text | str contains $pair.1)) $"luks ($c.name): ($pair.0 | to nuon) lacks ($pair.1)"
        }
    }
}

def crash-cases [dir: path]: nothing -> nothing {
    let file = $dir | path join crash.json
    assert equal (crash-reports [$file] | get level) [ok] "crash: no record"
    {run: "20261113T000849-q7jb", command: sync, error: "first line\nsecond"} | save $file
    let got = crash-reports [$file ($dir | path join absent.json)]
    assert equal ($got | get level) [note] $"crash: ($got | to nuon)"
    assert ($got.0.text | str contains "dot sync crashed in run 20261113T000849-q7jb and has not gone through since: first line;") $got.0.text
}

def packages-cases []: nothing -> nothing {
    let built = "2026-11-14T03:00:00+00:00" | into datetime
    let before = "new-tool 2026-11-13T12:00:00+00:00"
    let after = "new-tool 2026-11-15T12:00:00+00:00"
    let cases = [
        [name missing recorded built levels];
        ["nothing missing" [] [$after] $built [ok]]
        ["missing, never asked of the mirror" [htop] [] $built [FAIL]]
        ["asked after the last build" [new-tool] [$after] $built [note]]
        ["a build since the ask still lacks it" [new-tool] [$before] $built [FAIL]]
        ["no mirror database" [new-tool] [$after] null [FAIL]]
        ["one awaited, one not" [htop new-tool] [$after] $built [FAIL note]]
        ["a record of a name installed since" [htop] [$after] $built [FAIL]]
    ]
    for c in $cases {
        let got = packages-reports $c.missing $c.recorded $c.built
        assert equal ($got | get level) $c.levels $"packages ($c.name): ($got | to nuon)"
    }
    let mixed = packages-reports [htop new-tool] [$after] $built
    assert (($mixed.0.text | str contains htop) and not ($mixed.0.text | str contains new-tool)) $"packages: the FAIL names an awaited package: ($mixed.0.text)"
    assert ($mixed.1.text | str contains new-tool) $"packages: the note lacks the awaited name: ($mixed.1.text)"
}

def main []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-doctor-test-XXXXXX
    luks-cases
    packages-cases
    crash-cases $dir
    rm --recursive --force $dir
}
