#!/usr/bin/nu --no-config-file

const SELF = path self
const TARGET = "/etc/pacman.d/mirrorlist"
const LOCK = "/etc/pacman.d"
const HOMELAB_FILE = "/etc/pacman.d/homelab-mirror"
const COUNTRIES_FILE = "/etc/pacman.d/mirror-countries"
const COUNTRIES = "Germany,France,Switzerland,Austria,Poland,Denmark,Netherlands"
const MIRRORS_MAX = 30
const MIRRORS_MIN = 10
const USER_DEFINED = "## Used Defined"
const PROBE_TIMEOUT_S = 2
const HOMELAB_COMMENT = (
    "# homelab mirror: lan-direct at home and over wireguard, the public mirrors below are the away fallback"
)

def rank [mode: string, out: path]: nothing -> list<string> {
    if $mode == "sort" {
        ^ghostmirror -uml $TARGET $out -s light -S state,outofdate,morerecent,estimated,speed
    } else {
        let countries = try { open --raw $COUNTRIES_FILE | str trim } catch { "" }
            | if $in == "" { $COUNTRIES } else { $in }
        ^ghostmirror -l $out -c $countries -L $MIRRORS_MAX -T https -S state,outofdate,morerecent,ping
    }
    # https only: the databases are unsigned, a plain-http mirror could replay a stale one and hold updates back.
    open --raw $out | lines | where {|l| not ($l | str starts-with "Server=http://") }
}

def swap [lines: list<string>]: nothing -> nothing {
    $lines | str join "\n" | $"($in)\n" | save --force $"($TARGET).new"
    mv --force $"($TARGET).new" $TARGET
}

# Whether the mirror of a Server line serves core.db.
def answers [line: string]: nothing -> bool {
    let probe = $line | str replace "Server=" "" | str replace '$repo' core | str replace '$arch' x86_64
        | $"($in)/core.db"
    (^curl -fs -m $PROBE_TIMEOUT_S -r 0-0 -o /dev/null $probe | complete).exit_code == 0
}

# Drops every homelab entry whose Server line is not keep.
def homelab-drop [lines: list<string>, keep: string]: nothing -> list<string> {
    let drop = $lines | enumerate
        | where {|l| ($l.item | str starts-with "# homelab") and ($lines | get --optional ($l.index + 1)) != $keep }
        | each { [$in.index ($in.index + 1)] } | flatten
    $lines | enumerate | where index not-in $drop | get item
}

# Puts line first when its mirror answers and drops every other homelab entry; an empty line drops them all.
def homelab-place [line: string]: nothing -> nothing {
    let current = open --raw $TARGET | lines
    let kept = homelab-drop $current $line
    let missing = $line != "" and $line not-in $kept and (answers $line)
    let placed = if $missing { [$HOMELAB_COMMENT $line ""] ++ $kept } else { $kept }
    if $placed != $current { swap $placed }
}

def main [mode: string, line: string = ""]: nothing -> nothing {
    if $mode not-in [sort rebuild homelab] {
        print --stderr "usage: mirrorlist-update {sort|rebuild|homelab [Server=<url>]}"
        exit 2
    }
    if $env.MIRRORLIST_LOCKED? == null {
        with-env {MIRRORLIST_LOCKED: 1} { exec flock $LOCK $SELF $mode $line }
    }
    if $mode == "homelab" {
        homelab-place $line
        return
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
    # the homelab line is plain http, exempt from rank's filter as it is reached only over the home LAN or wireguard;
    # re-probed, so a network change since it was placed (away, wg0 down) does not leave pacman waiting on it
    let kept = $homelab != "" and $homelab in (open --raw $TARGET | lines) and (answers $homelab)
    let first = if $kept { [$HOMELAB_COMMENT $homelab ""] } else { [] }
    swap ($first ++ $public)
}
