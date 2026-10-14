#!/usr/bin/env -S nu --no-config-file
# millennium replaces libXtst in steam's runtime dirs, which exist only after steam's first run

const LIB = "/usr/lib/millennium"
const LINKS = [
    [lib target];
    [libmillennium_bootstrap_x86.so ubuntu12_32/libXtst.so.6]
    [libmillennium_bootstrap_hhx64.so ubuntu12_64/libXtst.so.6]
    [libmillennium_hhx64.so ubuntu12_64/libmillennium_hhx64.so]
]

def main []: nothing -> nothing {
    let steam = $nu.home-dir | path join .local share Steam
    let runtime = [ubuntu12_32 ubuntu12_64] | all {|d| $steam | path join $d | path exists }
    if not $runtime or not ($LIB | path exists) { return }
    for l in $LINKS { ^ln -sfn ($LIB | path join $l.lib) ($steam | path join $l.target) }
}
