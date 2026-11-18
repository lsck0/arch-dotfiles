#!/usr/bin/env -S nu --no-config-file
# vendor.nu's choice of what to install: the newest zip by version, nothing without a reachable vendor dir, and an
# install only when the NAS holds something newer than what is installed.
use vendor.nu [nas-vendor-newer nas-vendor-newest]

def fail [msg: string] { error make {msg: $"vendor.test: ($msg)"} }

def main [] {
    if (nas-vendor-newest null "jai-*.zip") != null { fail "an unreachable vendor dir yields a zip" }
    let dir = mktemp --directory --tmpdir vendor-test.XXXXXX
    if (nas-vendor-newest $dir "jai-*.zip") != null { rm -r $dir; fail "an empty vendor dir yields a zip" }
    ["jai-beta-2-9.zip" "jai-beta-2-030.zip" "jai-beta-2-10.zip" "Linux_Unreal_Engine_5.8.4.zip"]
        | each {|f| touch ($dir | path join $f) } | ignore
    let newest = nas-vendor-newest $dir "jai-*.zip" | path basename
    rm -r $dir
    if $newest != "jai-beta-2-030.zip" { fail $"newest jai zip: ($newest)" }
    let cases = [
        [installed candidate want];
        ["" "" false]
        ["" "jai-beta-2-030.zip" true]
        ["jai-beta-2-030.zip" "jai-beta-2-030.zip" false]
        ["jai-beta-2-030.zip" "jai-beta-2-031.zip" true]
        ["jai-beta-2-031.zip" "jai-beta-2-030.zip" false]
        ["jai-beta-2-030.zip" "" false]
        ["Linux_Unreal_Engine_5.8.4.zip" "Linux_Unreal_Engine_5.10.0.zip" true]
        ["d2launcher-mxl-2.14.6" "d2launcher-mxl-2.14.6" false]
        ["d2launcher-mxl-2.14.7" "d2launcher-mxl-2.14.6" false]
    ]
    for c in $cases {
        let got = nas-vendor-newer $c.installed $c.candidate
        if $got != $c.want { fail $"newer ($c.installed | to nuon) -> ($c.candidate | to nuon): ($got)" }
    }
}
