#!/usr/bin/nu --no-config-file
# runs as root from ghostmirror*.service; ranks into a temp dir so a short list never replaces the current one

const SELF = path self
const TARGET = "/etc/pacman.d/mirrorlist"
const LOCK = "/etc/pacman.d"
# the homelab mirror's Server= line on a homelab machine (mod.nu, its homelab_mirror option)
const HOMELAB_FILE = "/etc/pacman.d/homelab-mirror"
# bootstrap.sh writes the countries its measured ranking landed in; the owner's region without it
const COUNTRIES_FILE = "/etc/pacman.d/mirror-countries"
const COUNTRIES = "Germany,France,Switzerland,Austria,Poland,Denmark,Netherlands"
const MIRRORS_MAX = 30
# fewer servers means a failed fetch
const MIRRORS_MIN = 10
const USER_DEFINED = "## Used Defined"
const HOMELAB_COMMENT = (
    "# homelab mirror: lan-direct at home and over wireguard, the public mirrors below are the away fallback"
)

def rank [mode: string, out: path]: nothing -> list<string> {
    if $mode == "sort" {
        ^ghostmirror -uml $TARGET $out -s light -S state,outofdate,morerecent,estimated,speed
    } else {
        let countries = try { open --raw $COUNTRIES_FILE | str trim } catch { "" }
            | if $in == "" { $COUNTRIES } else { $in }
        ^ghostmirror -l $out -c $countries -L $MIRRORS_MAX -S state,outofdate,morerecent,ping
    }
    open --raw $out | lines
}

def main [mode: string]: nothing -> nothing {
    if $mode not-in [sort rebuild] {
        print --stderr "usage: mirrorlist-update {sort|rebuild}"
        exit 2
    }
    # the weekly sort and the monthly rebuild must not overwrite each other's list
    if $env.MIRRORLIST_LOCKED? == null {
        with-env {MIRRORLIST_LOCKED: 1} { exec flock $LOCK $SELF $mode }
    }
    let tmp = mktemp -d
    let ranked = try { rank $mode ($tmp | path join mirrorlist) } catch {|e| rm -rf $tmp; error make {msg: $e.msg} }
    rm -rf $tmp
    let homelab = try { open --raw $HOMELAB_FILE | str trim } catch { "" }
    # sort keeps the homelab line under the user-defined header; it is prepended below and never counts as public
    let public = $ranked | where {|l|
        not ($l | str contains $USER_DEFINED) and ($homelab == "" or not ($l | str contains $homelab))
    }
    let count = $public | where ($it | str starts-with Server) | length
    if $count < $MIRRORS_MIN {
        print --stderr $"mirrorlist-update: only ($count) servers, keeping the current list"
        exit 1
    }
    # homelab first (internal, authoritative), the ranked public mirrors are the away fallback; only where mod.nu put it
    let kept = $homelab != "" and $homelab in (open --raw $TARGET | lines)
    let first = if $kept { [$HOMELAB_COMMENT $homelab ""] } else { [] }
    $first ++ $public | str join "\n" | $"($in)\n" | save --force $"($TARGET).new"
    # rename, so pacman never reads a half-written list
    mv --force $"($TARGET).new" $TARGET
}
