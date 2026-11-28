#!/usr/bin/env -S nu --no-config-file
# vendor.nu's choice of what to install: the newest zip by version, nothing without a reachable vendor dir, and an
# install only when the NAS holds something newer than what is installed; a dir no install stamped is kept aside.
use std/assert
use scripts/vendor.nu [NAS_VENDOR_STAMP nas-vendor-newer nas-vendor-newest nas-vendor-plan nas-vendor-set-aside]

def main [] {
    assert equal (nas-vendor-newest null "jai-*.zip") null "an unreachable vendor dir yields a zip"
    let dir = mktemp --directory --tmpdir vendor-test.XXXXXX
    let empty = nas-vendor-newest $dir "jai-*.zip"
    ["jai-beta-2-9.zip" "jai-beta-2-030.zip" "jai-beta-2-10.zip" "Linux_Unreal_Engine_5.8.4.zip"]
        | each {|f| touch ($dir | path join $f) } | ignore
    let newest = nas-vendor-newest $dir "jai-*.zip" | path basename
    let plan = nas-vendor-plan $dir "jai-beta-2-10.zip" "jai-*.zip"
    let current = nas-vendor-plan $dir "jai-beta-2-030.zip" "jai-*.zip"
    let away = nas-vendor-plan null "jai-beta-2-030.zip" "jai-*.zip"
    let target = $dir | path join target
    mkdir $target
    touch ($target | path join $NAS_VENDOR_STAMP)
    nas-vendor-set-aside $target
    let stamped_kept = $target | path exists
    rm ($target | path join $NAS_VENDOR_STAMP)
    nas-vendor-set-aside $target
    let asides = glob ($dir | path join "target.pre-dotfiles-*") | length
    let foreign_moved = not ($target | path exists)
    rm -r $dir
    assert equal ($plan | reject zip) {name: "jai-beta-2-030.zip", newer: true, note: null} "a newer zip on the NAS"
    assert equal $current.newer false "the installed zip is the newest"
    assert equal ($away | reject zip) {name: "", newer: false, note: "the NAS vendor dir is not reachable, keeping jai-beta-2-030.zip"} "vendor away"
    assert equal (nas-vendor-plan null "" "jai-*.zip").note "the NAS vendor dir is not reachable, nothing installed" "away, none installed"
    assert $stamped_kept "a stamped dir stays in place"
    assert ($foreign_moved and $asides == 1) "an unstamped dir moves aside once"
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
