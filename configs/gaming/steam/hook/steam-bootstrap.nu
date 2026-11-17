#!/usr/bin/env -S nu --no-config-file
# after steam's first run: millennium patches libXtst in steam's runtime dirs. The 64-bit client runs in a
# pressure-vessel container (steamrt64) that sees the host's /usr only under /run/host; the 32-bit client needs
# millennium-x86, not installed, so its old link only goes

export const MILLENNIUM_LIB = "/usr/lib/millennium"
const LINKS = [
    [source target];
    [$"($MILLENNIUM_LIB)/libmillennium_bootstrap_hhx64.so" ubuntu12_64/libXtst.so.6]
    [$"($MILLENNIUM_LIB)/libmillennium_hhx64.so" ubuntu12_64/libmillennium_hhx64.so]
    [$"/run/host($MILLENNIUM_LIB)/libmillennium_bootstrap_x64.so" steamrt64/libXtst.so.6]
]
const STALE = "ubuntu12_32/libXtst.so.6"
# bin_steam.sh copies this into $XDG_DESKTOP_DIR (else ~/Desktop) unless a symlink is already there
const SHORTCUT_SOURCE = "/usr/lib/steam/steam.desktop"

# The millennium links steam's runtime still lacks; none before steam's first run made the runtime dirs.
def links-missing []: nothing -> list<record> {
    let steam = $nu.home-dir | path join .local share Steam
    let runtime = [ubuntu12_64 steamrt64] | all {|d| $steam | path join $d | path exists }
    if not $runtime or not ($MILLENNIUM_LIB | path exists) { return [] }
    $LINKS | each {|l| {source: $l.source, target: ($steam | path join $l.target)} }
    | where {|l| ($l.target | path type) != symlink or (^readlink $l.target | str trim) != $l.source }
}

# The 32-bit link only while it still points into millennium.
def stale-link []: nothing -> list<path> {
    let target = $nu.home-dir | path join .local share Steam $STALE
    if ($target | path type) != symlink { return [] }
    if (^readlink $target | str trim | str starts-with $"($MILLENNIUM_LIB)/") { [$target] } else { [] }
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
    (links-missing | is-not-empty) or (stale-link | is-not-empty) or (shortcuts-steam | is-not-empty)
}

def main []: nothing -> nothing {
    for l in (links-missing) { ^ln -sfn $l.source $l.target }
    for l in (stale-link) { rm $l }
    for s in (shortcuts-steam) { rm $s }
}
