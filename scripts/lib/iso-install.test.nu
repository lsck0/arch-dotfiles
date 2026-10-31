#!/usr/bin/env -S nu --no-config-file
# Table cases for picking the install's answer file: the second stage's reading of the stub's pick, and the stub's
# broken-file marking, dedupe, menu timeout, source staging and dialog exits.
const STUB = path self ../../mirror/iso/airootfs/usr/local/bin/lsck0-install
use iso-install.nu [answers-handed]
use $STUB [answers-check answers-dedupe answers-menu-timeout answers-stage-plan answers-source-staged dlg-kind]

def fail [msg: string] { error make {msg: $"iso-install.test: ($msg)"} }

def handed-check [] {
    let cases = [
        [name handed text wants];
        ["no pick scans the media" "" null {scan: true, answers: null}]
        ["none scans nothing" "none" null {scan: false, answers: null}]
        ["a file is its answers" "/run/lsck0/a/lsck0.nuon" "{disk: /dev/vda}" {scan: false, answers: {disk: /dev/vda, origin: "usb:lsck0.nuon"}}]
    ]
    for c in $cases {
        let got = answers-handed $c.handed "usb:lsck0.nuon" $c.text
        if $got != $c.wants { fail $"handed, ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
    let broken = [[name text]; ["not nuon" "{disk: "] ["not a record" "[1 2]"] ["unreadable" null]]
    for c in $broken {
        let got = try { answers-handed "/run/lsck0/a/lsck0.nuon" "usb:lsck0.nuon" $c.text; "no error" } catch {|e| $e.msg }
        if not ($got =~ '^usb:lsck0\.nuon: .*nothing installed') { fail $"handed, ($c.name): ($got), wants a stop naming the file" }
    }
}

def check-check [] {
    let cases = [
        [name text wants];
        ["record" "{unattended: true}" '^$']
        ["unclosed" "{\n  disk: /dev/vda\n" '^not nuon, line \d+: ']
        ["bad field" "{\n  disk: a b\n}" '^not nuon, line 2: ']
        ["list" "[1]" '^not a record$']
        ["empty" "" '^not a record$']
    ]
    for c in $cases {
        let got = answers-check $c.text
        if not ($got =~ $c.wants) { fail $"check, ($c.name): got ($got | to nuon), wants ($c.wants)" }
    }
}

def found [origin: string, real: string, hash: string]: nothing -> record {
    {origin: $origin, real: $real, hash: $hash}
}

def dedupe-check [] {
    let boot = found /run/archiso/bootmnt/lsck0.nuon /run/archiso/bootmnt/lsck0.nuon h1
    let cases = [
        [name found wants];
        ["the boot medium scanned again" [$boot (found /dev/sda1:lsck0.nuon /run/archiso/bootmnt/lsck0.nuon h1)] [$boot.origin]]
        ["one file on two media" [$boot (found /dev/sdb1:lsck0.nuon /run/lsck0/mnt/sdb1/lsck0.nuon h1)] [$boot.origin]]
        ["two files" [$boot (found /dev/sdb1:lsck0.vm.nuon /run/lsck0/mnt/sdb1/lsck0.vm.nuon h2)] [$boot.origin /dev/sdb1:lsck0.vm.nuon]]
        ["none" [] []]
    ]
    for c in $cases {
        let got = answers-dedupe $c.found | get --optional origin | default []
        if $got != $c.wants { fail $"dedupe, ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}

def menu-timeout-check [] {
    let cases = [
        [name usable wants];
        ["first unattended" [{unattended: true} {unattended: false}] 10sec]
        ["only a later one unattended" [{unattended: false} {unattended: true}] 0sec]
        ["none unattended" [{unattended: false} {unattended: false}] 0sec]
        ["two unattended, one stick for two machines" [{unattended: true} {unattended: true}] 0sec]
    ]
    for c in $cases {
        let got = answers-menu-timeout $c.usable
        if $got != $c.wants { fail $"menu timeout, ($c.name): got ($got), wants ($c.wants)" }
    }
}

def picked [rel: string, text: string]: nothing -> record {
    {rel: $rel, text: $text, hash: ($text | hash sha256)}
}

def stage-plan-check [] {
    let a = picked lsck0.nuon "{source: {bundle: repo.bundle, lfs: /abs/lfs.tar}}"
    let b = picked iso/lsck0.vm.nuon "{source: {bundle: repo.bundle, lfs: \"https://x/lfs.tar\"}}"
    let pa = answers-stage-plan $a /run/lsck0 /media/a
    let pb = answers-stage-plan $b /run/lsck0 /media/b/iso
    if $pa.dir == $pb.dir { fail $"stage plan: two files share ($pa.dir)" }
    if $pa.copy != ($pa.dir | path join lsck0.nuon) { fail $"stage plan: copy ($pa.copy)" }
    let want_a = [
        {key: bundle, path: repo.bundle, from: /media/a/repo.bundle, to: ($pa.dir | path join repo.bundle)}
        {key: lfs, path: /abs/lfs.tar, from: /abs/lfs.tar, to: ($pa.dir | path join lfs.tar)}
    ]
    if $pa.sources != $want_a { fail $"stage plan: sources ($pa.sources | to nuon), wants ($want_a | to nuon)" }
    if ($pb.sources | get from) != [/media/b/iso/repo.bundle] { fail $"stage plan: a url is staged or the bundle missed: ($pb.sources | to nuon)" }
    # checkout-bundle looks where staging put it
    if (answers-source-staged ($pb.copy | path dirname) repo.bundle) != ($pb.sources.0.to) { fail "stage plan: checkout looks elsewhere than staging puts" }
    let none = answers-stage-plan (picked lsck0.nuon "{disk: /dev/vda}") /run/lsck0 /media/a
    if $none.sources != [] { fail $"stage plan: sources without a source ($none.sources | to nuon)" }
}

def dlg-kind-check [] {
    let cases = [
        [name code err timeout elapsed wants];
        ["ok" 0 "" 0sec 1sec ok]
        ["no" 1 "" 0sec 1sec cancel]
        ["esc" 255 "" 0sec 1sec esc]
        ["esc before the timeout" 255 "" 10sec 3sec esc]
        ["timeout code" 5 "" 10sec 10sec timeout]
        ["timeout read as esc" 255 "" 10sec 10sec timeout]
        ["error as 255 with stderr" 255 "Error: Expected at least 6 tokens" 0sec 0sec error]
        ["error code" 6 "" 0sec 0sec error]
        ["unknown code" 3 "" 0sec 0sec error]
    ]
    for c in $cases {
        let got = dlg-kind $c.code $c.err $c.timeout $c.elapsed
        if $got != $c.wants { fail $"dlg kind, ($c.name): got ($got), wants ($c.wants)" }
    }
}

def main [] {
    handed-check
    check-check
    dedupe-check
    menu-timeout-check
    stage-plan-check
    dlg-kind-check
}
