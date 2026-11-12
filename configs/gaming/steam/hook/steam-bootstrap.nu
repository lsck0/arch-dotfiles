#!/usr/bin/env -S nu --no-config-file
# after steam's first run: millennium patches libXtst in steam's runtime dirs

export const MILLENNIUM_LIB = "/usr/lib/millennium"
const LINKS = [
    [lib target];
    [libmillennium_bootstrap_x86.so ubuntu12_32/libXtst.so.6]
    [libmillennium_bootstrap_hhx64.so ubuntu12_64/libXtst.so.6]
    [libmillennium_hhx64.so ubuntu12_64/libmillennium_hhx64.so]
]
# bin_steam.sh copies this into $XDG_DESKTOP_DIR (else ~/Desktop) unless a symlink is already there
const SHORTCUT_SOURCE = "/usr/lib/steam/steam.desktop"

# The millennium links steam's runtime still lacks; none before steam's first run made the runtime dirs.
def links-missing []: nothing -> list<record> {
    let steam = $nu.home-dir | path join .local share Steam
    let runtime = [ubuntu12_32 ubuntu12_64] | all {|d| $steam | path join $d | path exists }
    if not $runtime or not ($MILLENNIUM_LIB | path exists) { return [] }
    $LINKS | each {|l| {source: ($MILLENNIUM_LIB | path join $l.lib), target: ($steam | path join $l.target)} }
    | where {|l| ($l.target | path type) != symlink or (^readlink $l.target | str trim) != $l.source }
}

# Only steam's own copy goes, a launcher the user put there stays.
def shortcuts-steam []: nothing -> list<path> {
    if not ($SHORTCUT_SOURCE | path exists) { return [] }
    let desktop = try { ^xdg-user-dir DESKTOP | str trim } catch { "" }
    let source = open --raw $SHORTCUT_SOURCE
    [$desktop ($nu.home-dir | path join Desktop)] | where $it != "" | uniq | each { path join steam.desktop }
    | where {|s| ($s | path type) == file and (open --raw $s) == $source }
}

export def bootstrap-pending []: nothing -> bool {
    (links-missing | is-not-empty) or (shortcuts-steam | is-not-empty)
}

def main []: nothing -> nothing {
    for l in (links-missing) { ^ln -sfn $l.source $l.target }
    for s in (shortcuts-steam) { rm $s }
}
