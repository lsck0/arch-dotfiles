#!/usr/bin/nu --no-config-file

const SELF = path self
const TARGET = "/etc/pacman.d/mirrorlist"
const LOCK = "/etc/pacman.d"
const HOMELAB_FILE = "/etc/pacman.d/homelab-mirror"
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
    # sort keeps the homelab line under the user-defined header; it is prepended again below
    let public = $ranked | where {|l|
        not ($l | str contains $USER_DEFINED) and ($homelab == "" or not ($l | str contains $homelab))
    }
    let count = $public | where ($it | str starts-with Server) | length
    if $count < $MIRRORS_MIN {
        print --stderr $"mirrorlist-update: only ($count) servers, keeping the current list"
        exit 1
    }
    let kept = $homelab != "" and $homelab in (open --raw $TARGET | lines)
    let first = if $kept { [$HOMELAB_COMMENT $homelab ""] } else { [] }
    $first ++ $public | str join "\n" | $"($in)\n" | save --force $"($TARGET).new"
    mv --force $"($TARGET).new" $TARGET
}
