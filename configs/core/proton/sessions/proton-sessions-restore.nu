#!/usr/bin/env -S nu --no-config-file
# The first login after a reinstall: restores the Proton sign-ins before any app starts, once the keyring is open.

const HERE = path self | path expand | path dirname
const REPO = path self | path expand | path dirname --num-levels 5
use ($HERE | path join sessions.nu) [sessions-archives sessions-restore sessions-settle]
use ($REPO | path join scripts lib secrets.nu) [secret-is-plaintext OWNER_WITNESS]

def main [] {
    if not (secret-is-plaintext ($REPO | path join $OWNER_WITNESS)) {
        print "dotfiles secrets locked: dot apply core/proton/sessions restores once they are unlocked"
        return
    }
    let statuses = sessions-restore (sessions-archives $REPO)
    $statuses | where status != none | each {|row| print $"($row.app): ($row.status)" } | ignore
    sessions-settle $statuses
}
