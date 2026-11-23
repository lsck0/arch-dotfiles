#!/usr/bin/env -S nu --no-config-file
# vendor.nu's choice of what to install: the newest zip by version, nothing without a reachable vendor dir, and an
# install only when the NAS holds something newer than what is installed.
use std/assert
use vendor.nu [nas-vendor-newer nas-vendor-newest]

def main [] {
    assert equal (nas-vendor-newest null "jai-*.zip") null "an unreachable vendor dir yields a zip"
    let dir = mktemp --directory --tmpdir vendor-test.XXXXXX
    let empty = nas-vendor-newest $dir "jai-*.zip"
    ["jai-beta-2-9.zip" "jai-beta-2-030.zip" "jai-beta-2-10.zip" "Linux_Unreal_Engine_5.8.4.zip"]
        | each {|f| touch ($dir | path join $f) } | ignore
    let newest = nas-vendor-newest $dir "jai-*.zip" | path basename
    rm -r $dir
    assert equal $empty null "an empty vendor dir yields a zip"
    assert equal $newest "jai-beta-2-030.zip" "newest jai zip"
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
        assert equal (nas-vendor-newer $c.installed $c.candidate) $c.want $"newer ($c.installed | to nuon) -> ($c.candidate | to nuon)"
    }
}
