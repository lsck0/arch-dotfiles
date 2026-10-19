#!/usr/bin/env -S nu --no-config-file
# after steam's first run: millennium replaces libXtst in steam's runtime dirs, which exist only from then on, and the
# bootstrap's copy of steam.desktop leaves the desktop dir

const LIB = "/usr/lib/millennium"
const LINKS = [
    [lib target];
    [libmillennium_bootstrap_x86.so ubuntu12_32/libXtst.so.6]
    [libmillennium_bootstrap_hhx64.so ubuntu12_64/libXtst.so.6]
    [libmillennium_hhx64.so ubuntu12_64/libmillennium_hhx64.so]
]
# bin_steam.sh copies this into $XDG_DESKTOP_DIR (else ~/Desktop) unless a symlink is already there
const SHORTCUT_SOURCE = "/usr/lib/steam/steam.desktop"

def millennium-link []: nothing -> nothing {
    let steam = $nu.home-dir | path join .local share Steam
    let runtime = [ubuntu12_32 ubuntu12_64] | all {|d| $steam | path join $d | path exists }
    if not $runtime or not ($LIB | path exists) { return }
    for l in $LINKS { ^ln -sfn ($LIB | path join $l.lib) ($steam | path join $l.target) }
}

# only steam's own copy goes, a launcher the user put there stays
def shortcut-remove []: nothing -> nothing {
    if not ($SHORTCUT_SOURCE | path exists) { return }
    let desktop = try { ^xdg-user-dir DESKTOP | str trim } catch { "" }
    let source = open --raw $SHORTCUT_SOURCE
    for dir in ([$desktop ($nu.home-dir | path join Desktop)] | where $it != "" | uniq) {
        let shortcut = $dir | path join steam.desktop
        if ($shortcut | path type) == file and (open --raw $shortcut) == $source { rm $shortcut }
    }
}

def main []: nothing -> nothing {
    millennium-link
    shortcut-remove
}
