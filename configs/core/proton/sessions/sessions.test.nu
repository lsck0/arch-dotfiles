#!/usr/bin/env -S nu --no-config-file
# The keyring-free half of the session round trip on a fake Proton Pass: backup, a byte-stable second backup, restore
# into an empty home, and a restore that keeps a live session.

use sessions.nu [APPS session-backup session-restore]

const LIVE_MARK = "live-session"

def fail [msg: string] { error make {msg: $"sessions.test: ($msg)"} }

def main [] {
    let work = mktemp --directory
    try {
        let pass = $APPS | where name == pass | first
        let old = $work | path join old
        let new = $work | path join new
        let archive = $work | path join archives pass.tar
        let app = $old | path join "Proton Pass" Partitions app
        mkdir ($app | path join "Local Storage" leveldb)
        ^sqlite3 ($app | path join Cookies) "create table cookies (host_key text, name text); insert into cookies values ('pass.proton.me', 'REFRESH-x');"
        "ps-1" | save ($app | path join "Local Storage" leveldb 000003.log)
        "" | save ($app | path join "Local Storage" leveldb LOCK)

        with-env {XDG_CONFIG_HOME: $old} {
            if not (session-backup $pass $archive) { fail "a live session was not backed up" }
            let first = open --raw $archive | hash sha256
            session-backup $pass $archive | ignore
            if (open --raw $archive | hash sha256) != $first { fail "an unchanged session changed the archive" }
        }
        let members = ^tar --list --file $archive | lines
        if ($members | any { str ends-with LOCK }) { fail "leveldb's LOCK was archived" }

        with-env {XDG_CONFIG_HOME: $new} {
            let status = session-restore $pass $archive
            if $status != restored { fail $"want restored into an empty home, got ($status)" }
            let restored = $new | path join "Proton Pass" Partitions app
            let rows = ^sqlite3 ($restored | path join Cookies) "select name from cookies" | str trim
            if $rows != "REFRESH-x" { fail $"restored cookies hold ($rows)" }
            if (open --raw ($restored | path join "Local Storage" leveldb 000003.log)) != "ps-1" { fail "local storage not restored" }
            if (^stat -c %a ($new | path join "Proton Pass") | str trim) != "700" { fail "the app dir is not private" }

            $LIVE_MARK | save --force ($restored | path join "Local Storage" leveldb 000003.log)
            let again = session-restore $pass $archive
            if $again != live { fail $"want live on a second restore, got ($again)" }
            if (open --raw ($restored | path join "Local Storage" leveldb 000003.log)) != $LIVE_MARK { fail "a live session was replaced" }
        }
        if (session-restore $pass ($work | path join absent.tar)) != none { fail "a missing archive is not none" }
    } catch {|e|
        ^rm -rf $work
        error make $e.raw
    }
    ^rm -rf $work
}
