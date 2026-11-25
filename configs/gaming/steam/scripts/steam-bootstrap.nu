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

# The 32-bit link, and with millennium off every link, only while it still points into millennium.
def stale-link [millennium: bool]: nothing -> list<path> {
    let steam = $nu.home-dir | path join .local share Steam
    let targets = if $millennium { [$STALE] } else { $LINKS.target | append $STALE }
    $targets | each {|t| $steam | path join $t } | where ($it | path type) == symlink | where {|t|
        let source = ^readlink $t | str trim
        [$MILLENNIUM_LIB $"/run/host($MILLENNIUM_LIB)"] | any {|lib| $source | str starts-with $"($lib)/" }
    }
}

# Only steam's own copy goes, a launcher the user put there stays.
def shortcuts-steam []: nothing -> list<path> {
    if not ($SHORTCUT_SOURCE | path exists) { return [] }
    let desktop = try { ^xdg-user-dir DESKTOP | str trim } catch { "" }
    let source = open --raw $SHORTCUT_SOURCE
    [$desktop ($nu.home-dir | path join Desktop)] | where $it != "" | uniq | each { path join steam.desktop }
    | where {|s| ($s | path type) == file and (open --raw $s) == $source }
}

# --no-millennium: gaming/steam's millennium option is off, its links go instead.
export def bootstrap-pending [--no-millennium]: nothing -> bool {
    let missing = if $no_millennium { [] } else { links-missing }
    ($missing | is-not-empty) or (stale-link (not $no_millennium) | is-not-empty) or (shortcuts-steam | is-not-empty)
}

def main [--no-millennium]: nothing -> nothing {
    if not $no_millennium { for l in (links-missing) { ^ln -sfn $l.source $l.target } }
    for l in (stale-link (not $no_millennium)) { rm $l }
    for s in (shortcuts-steam) { rm $s }
}
